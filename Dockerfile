# Dockerfile for TI Sync Service - Mock API to Sentinel
FROM mcr.microsoft.com/powershell:7.5-alpine-3.20

# Install required packages
RUN apk add --no-cache \
    ca-certificates \
    curl \
    tzdata \
    bash \
    jq

# Set timezone
ENV TZ=UTC

# Set default environment variables (can be overridden)
ENV SYNC_MODE=Continuous
ENV INTERVAL_MINUTES=180
ENV MOCK_API_URL=http://mock-ti-api:8080
ENV SHOW_PROGRESS=false
ENV ENV_FILE=/app/config/.env

# Create working directory and subdirectories
WORKDIR /app
RUN mkdir -p /app/modules /app/config /app/output /app/logs

# Copy PowerShell modules and driver script
COPY ./Invoke-TI2UploadAPI.psm1 /app/modules/Invoke-TI2UploadAPI.psm1
COPY ./Start-TISyncFromMockAPI.psm1 /app/modules/Start-TISyncFromMockAPI.psm1
COPY ./TI-Sync-Driver.ps1 /app/TI-Sync-Driver.ps1

# Create a wrapper script for better Docker signal handling
RUN cat <<'EOF' > /app/docker-entrypoint.sh
#!/bin/bash
set -e

# Function to handle termination signals
cleanup() {
    echo "Received termination signal, shutting down gracefully..."
    exit 0
}

# Trap termination signals
trap cleanup SIGTERM SIGINT

# Check if .env file exists
if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: Environment file not found at $ENV_FILE"
    echo "Please mount your .env file to /app/config/.env"
    exit 1
fi

# Convert SHOW_PROGRESS to PowerShell switch format
if [ "$SHOW_PROGRESS" = "true" ]; then
    PROGRESS_FLAG="-ShowProgress"
else
    PROGRESS_FLAG=""
fi

# Execute based on SYNC_MODE
case "$SYNC_MODE" in
    "Single")
        echo "Running single sync operation..."
        exec pwsh -NoProfile -Command "& /app/TI-Sync-Driver.ps1 -Mode Single -MockApiUrl '$MOCK_API_URL' -EnvFile '$ENV_FILE' $PROGRESS_FLAG"
        ;;
    "Once")
        echo "Running one-time sync..."
        exec pwsh -NoProfile -Command "& /app/TI-Sync-Driver.ps1 -Mode Once -MockApiUrl '$MOCK_API_URL' -EnvFile '$ENV_FILE' $PROGRESS_FLAG"
        ;;
    "Continuous")
        echo "Starting continuous sync service (interval: $INTERVAL_MINUTES minutes)..."
        exec pwsh -NoProfile -Command "& /app/TI-Sync-Driver.ps1 -Mode Continuous -IntervalMinutes '$INTERVAL_MINUTES' -MockApiUrl '$MOCK_API_URL' -EnvFile '$ENV_FILE' $PROGRESS_FLAG"
        ;;
    "Test")
        echo "Running in test mode (no upload)..."
        exec pwsh -NoProfile -Command "& /app/TI-Sync-Driver.ps1 -Mode Test -MockApiUrl '$MOCK_API_URL' -EnvFile '$ENV_FILE' -SaveToFile"
        ;;
    *)
        echo "Invalid SYNC_MODE: $SYNC_MODE"
        echo "Valid modes: Single, Once, Continuous, Test"
        exit 1
        ;;
esac
EOF

# Make scripts executable (psm1 files don't need execute permission, but ps1 does)
RUN chmod +x /app/docker-entrypoint.sh && \
    chmod +x /app/TI-Sync-Driver.ps1

# Create a startup script that properly loads modules
RUN cat <<'EOF' > /app/Start-Service.ps1
# Start-Service.ps1 - Docker startup script
param(
    [string]$Mode = $env:SYNC_MODE,
    [int]$IntervalMinutes = [int]$env:INTERVAL_MINUTES,
    [string]$MockApiUrl = $env:MOCK_API_URL,
    [string]$EnvFile = $env:ENV_FILE,
    [string]$ShowProgressStr = $env:SHOW_PROGRESS
)

# Convert string to switch
$ShowProgress = $ShowProgressStr -eq 'true'

# Set location to app directory
Set-Location /app

# Import PowerShell modules (.psm1 files)
Write-Host "Loading TI Sync modules..." -ForegroundColor Cyan
Import-Module /app/modules/Invoke-TI2UploadAPI.psm1 -Force -DisableNameChecking
Import-Module /app/modules/Start-TISyncFromMockAPI.psm1 -Force -DisableNameChecking

# Verify modules loaded
if (-not (Get-Command Invoke-TI2UploadAPI -ErrorAction SilentlyContinue)) {
    Write-Error "Failed to load Invoke-TI2UploadAPI module"
    exit 1
}
if (-not (Get-Command Start-TISyncFromMockAPI -ErrorAction SilentlyContinue)) {
    Write-Error "Failed to load Start-TISyncFromMockAPI module"
    exit 1
}

Write-Host "✓ Modules loaded successfully" -ForegroundColor Green

# Execute based on mode
Write-Host "Starting TI Sync Service in $Mode mode..." -ForegroundColor Yellow

switch ($Mode) {
    "Single" {
        Invoke-TI2UploadAPI -EnvFile $EnvFile -MockApiUrl $MockApiUrl -ShowProgress:$ShowProgress
    }
    "Once" {
        Start-TISyncFromMockAPI -RunOnce -EnvFile $EnvFile -MockApiUrl $MockApiUrl -ShowProgress:$ShowProgress
    }
    "Continuous" {
        Start-TISyncFromMockAPI -IntervalMinutes $IntervalMinutes -EnvFile $EnvFile -MockApiUrl $MockApiUrl -ShowProgress:$ShowProgress
    }
    "Test" {
        Invoke-TI2UploadAPI -EnvFile $EnvFile -MockApiUrl $MockApiUrl -TestMode -SaveToFile -ShowProgress
    }
    default {
        Write-Error "Invalid mode: $Mode"
        exit 1
    }
}
EOF

ENV DOCKER_CONTAINER=true
RUN chmod +x /app/Start-Service.ps1

# remove root from container
RUN adduser --disabled-password appuser && chown -R appuser /app
USER appuser

# Health check: Verify Mock API connectivity
# This ensures the ti-sync-service can reach the mock-ti-api which is required for operation
#HEALTHCHECK --interval=5m --timeout=10s --start-period=30s --retries=3 \
#    CMD curl -f http://mock-ti-api:8000/healthz || exit 1

# Use bash entrypoint for better signal handling
ENTRYPOINT ["/app/docker-entrypoint.sh"]
