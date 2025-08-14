# TI-Sync-Driver.ps1
# Main driver script for TI Sync Service
# Simplified for containerized deployment

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("Single", "Continuous", "Test", "Once", "Help")]
    [string]$Mode = "Help",
    
    [Parameter(Mandatory = $false)]
    [int]$IntervalMinutes = 120,
    
    [Parameter(Mandatory = $false)]
    [string]$MockApiUrl = "http://mock-ti-api:8080",
    
    [Parameter(Mandatory = $false)]
    [string]$EnvFile = "/app/config/.env",
    
    [Parameter(Mandatory = $false)]
    [switch]$ShowProgress,
    
    [Parameter(Mandatory = $false)]
    [switch]$SaveToFile
)

# Script information
$scriptVersion = "1.3.37b"
$scriptName = "TI Sync Driver"

# Function to display banner
function Show-Banner {
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║          TI SYNC SERVICE - MOCK API TO SENTINEL           ║" -ForegroundColor Cyan
    Write-Host "║                     Version $scriptVersion                       ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

# Function to import modules - simplified for Docker
function Import-TIModules {
    Write-Host "Loading TI Sync modules..." -ForegroundColor Cyan
    
    try {
        # In Docker, modules are always at /app/modules
        # For local development, check current directory first
        $modulePaths = @(
            "/app/modules",           # Docker location
            "./modules",              # Local relative path
            "."                       # Current directory
        )
        
        $uploadModuleFound = $false
        $syncModuleFound = $false
        
        foreach ($path in $modulePaths) {
            if (-not $uploadModuleFound) {
                $uploadPath = Join-Path $path "Invoke-TI2UploadAPI.psm1"
                if (Test-Path $uploadPath) {
                    Import-Module $uploadPath -Force -DisableNameChecking -ErrorAction Stop
                    Write-Host "  ✓ Loaded Invoke-TI2UploadAPI from $path" -ForegroundColor Green
                    $uploadModuleFound = $true
                }
            }
            
            if (-not $syncModuleFound) {
                $syncPath = Join-Path $path "Start-TISyncFromMockAPI.psm1"
                if (Test-Path $syncPath) {
                    Import-Module $syncPath -Force -DisableNameChecking -ErrorAction Stop
                    Write-Host "  ✓ Loaded Start-TISyncFromMockAPI from $path" -ForegroundColor Green
                    $syncModuleFound = $true
                }
            }
            
            if ($uploadModuleFound -and $syncModuleFound) {
                break
            }
        }
        
        # Verify functions are available
        if (-not (Get-Command Invoke-TI2UploadAPI -ErrorAction SilentlyContinue)) {
            throw "Invoke-TI2UploadAPI function not found after module import"
        }
        
        if (-not (Get-Command Start-TISyncFromMockAPI -ErrorAction SilentlyContinue)) {
            throw "Start-TISyncFromMockAPI function not found after module import"
        }
        
        Write-Host "✓ All modules loaded successfully" -ForegroundColor Green
        return $true
        
    } catch {
        Write-Error "Failed to load modules: $_"
        Write-Host "`nPlease ensure the following files exist:" -ForegroundColor Yellow
        Write-Host "  - Invoke-TI2UploadAPI.psm1" -ForegroundColor Gray
        Write-Host "  - Start-TISyncFromMockAPI.psm1" -ForegroundColor Gray
        return $false
    }
}

# Function to display help
function Show-Help {
    Write-Host "Usage: .\TI-Sync-Driver.ps1 -Mode <mode> [options]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "MODES:" -ForegroundColor Cyan
    Write-Host "  Single      - Run a single sync operation with progress display" -ForegroundColor White
    Write-Host "  Once        - Run a single sync operation (minimal output)" -ForegroundColor White
    Write-Host "  Continuous  - Run continuous sync on schedule" -ForegroundColor White
    Write-Host "  Test        - Test mode (fetch only, no upload)" -ForegroundColor White
    Write-Host "  Help        - Display this help message" -ForegroundColor White
    Write-Host ""
    Write-Host "OPTIONS:" -ForegroundColor Cyan
    Write-Host "  -IntervalMinutes <int>    Sync interval in minutes (default: 180)" -ForegroundColor White
    Write-Host "  -MockApiUrl <string>      Mock API URL (default: http://192.168.10.27)" -ForegroundColor White
    Write-Host "  -EnvFile <string>         Path to .env file (default: .\.env)" -ForegroundColor White
    Write-Host "  -ShowProgress             Show detailed progress information" -ForegroundColor White
    Write-Host "  -SaveToFile               Save fetched indicators to file (Test mode)" -ForegroundColor White
    Write-Host ""
    Write-Host "EXAMPLES:" -ForegroundColor Cyan
    Write-Host "  # Run single sync with progress:" -ForegroundColor Gray
    Write-Host "  .\TI-Sync-Driver.ps1 -Mode Single" -ForegroundColor White
    Write-Host ""
    Write-Host "  # Run continuous sync every 60 minutes:" -ForegroundColor Gray
    Write-Host "  .\TI-Sync-Driver.ps1 -Mode Continuous -IntervalMinutes 60" -ForegroundColor White
    Write-Host ""
    Write-Host "  # Test connection without uploading:" -ForegroundColor Gray
    Write-Host "  .\TI-Sync-Driver.ps1 -Mode Test -SaveToFile" -ForegroundColor White
    Write-Host ""
}

# Function to test Mock API connectivity
function Test-MockAPIConnection {
    param ([string]$ApiUrl)

    Write-Host "[TI-Sync-Driver] Testing Mock API connectivity..." -ForegroundColor Cyan

    try {
        $healthUrl = "$ApiUrl/healthz"
        $response = Invoke-RestMethod -Uri $healthUrl -Method GET -TimeoutSec 5
        
        if ($response.status -eq "ok") {
            Write-Host "✓ [TI-Sync-Driver] Mock API is reachable and healthy" -ForegroundColor Green
            return $true
        } else {
            Write-Host "⚠ [TI-Sync-Driver] Mock API returned unexpected status: $($response.status)" -ForegroundColor Yellow
            return $false
        }
    } catch {
        Write-Host "✗ [TI-Sync-Driver] Failed to connect to Mock API at $ApiUrl" -ForegroundColor Red
        Write-Host "  Error: $_" -ForegroundColor Gray
        return $false
    }
}

# Main execution
Show-Banner

# Check if .env file exists (only basic check)
if ($Mode -ne "Help" -and -not (Test-Path $EnvFile)) {
    Write-Warning "Environment file not found at: $EnvFile"
    Write-Host "Continue anyway? (y/N): " -ForegroundColor Yellow -NoNewline
    $continue = Read-Host
    if ($continue -ne 'y' -and $continue -ne 'Y') {
        Write-Host "Exiting..." -ForegroundColor Gray
        exit 1
    }
}

# Load modules
if ($Mode -ne "Help") {
    if (-not (Import-TIModules)) {
        exit 1
    }
}

# Test API connectivity (except for Help mode)
if ($Mode -ne "Help") {
    Write-Host ""
    if (-not (Test-MockAPIConnection -ApiUrl $MockApiUrl)) {
        Write-Host "Continue anyway? (y/N): " -ForegroundColor Yellow -NoNewline
        $continue = Read-Host
        if ($continue -ne 'y' -and $continue -ne 'Y') {
            Write-Host "Exiting..." -ForegroundColor Gray
            exit 1
        }
    }
}

# Execute based on mode
Write-Host "`n" -NoNewline
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "Executing Mode: $Mode" -ForegroundColor Yellow
Write-Host ("=" * 60) -ForegroundColor Cyan

switch ($Mode) {
    "Single" {
        Write-Host "`nRunning single sync with progress display..." -ForegroundColor Yellow
        $result = Invoke-TI2UploadAPI -EnvFile $EnvFile -MockApiUrl $MockApiUrl -ShowProgress
        
        if ($result -and $result.SuccessfulBatches -gt 0) {
            Write-Host "`n✓ Single sync completed successfully" -ForegroundColor Green
            Write-Host "  Total Indicators: $($result.TotalIndicators)" -ForegroundColor White
            Write-Host "  Uploaded: $($result.UploadedIndicators)" -ForegroundColor White
        } else {
            Write-Host "`n✗ Single sync failed or no indicators uploaded" -ForegroundColor Red
        }
    }
    
    "Once" {
        Write-Host "`nRunning single sync operation..." -ForegroundColor Yellow
        $result = Start-TISyncFromMockAPI -RunOnce -EnvFile $EnvFile -MockApiUrl $MockApiUrl -ShowProgress:$ShowProgress
        
        if ($result -and $result.SuccessfulBatches -gt 0) {
            Write-Host "`n✓ Operation completed" -ForegroundColor Green
        } else {
            Write-Host "`n✗ Operation failed" -ForegroundColor Red
        }
    }
    
    "Continuous" {
        Write-Host "`n[TI-Sync-Driver] Starting continuous sync service..." -ForegroundColor Yellow
        Write-Host "[TI-Sync-Driver] Interval: Every $IntervalMinutes minutes" -ForegroundColor Gray
        Write-Host "[TI-Sync-Driver] Mock API: $MockApiUrl" -ForegroundColor Gray
        Write-Host ""
        
        Start-TISyncFromMockAPI -IntervalMinutes $IntervalMinutes -EnvFile $EnvFile -MockApiUrl $MockApiUrl -ShowProgress:$ShowProgress
    }
    
    "Test" {
        Write-Host "`nRunning in TEST MODE (no upload to Sentinel)..." -ForegroundColor Yellow
        
        $testParams = @{
            EnvFile = $EnvFile
            MockApiUrl = $MockApiUrl
            TestMode = $true
            ShowProgress = $true
        }
        
        if ($SaveToFile) {
            $testParams['SaveToFile'] = $true
        }
        
        $result = Invoke-TI2UploadAPI @testParams
        
        if ($result) {
            Write-Host "`n✓ Test completed successfully" -ForegroundColor Green
            Write-Host "  Indicators found: $($result.stixobjects.Count)" -ForegroundColor White
            Write-Host "  Source System: $($result.sourcesystem)" -ForegroundColor White
            
            if ($SaveToFile) {
                Write-Host "  Check the saved JSON file for details" -ForegroundColor Gray
            }
        } else {
            Write-Host "`n✗ Test failed" -ForegroundColor Red
        }
    }
    
    "Help" {
        Show-Help
    }
    
    default {
        Write-Host "Invalid mode specified: $Mode" -ForegroundColor Red
        Write-Host ""
        Show-Help
        exit 1
    }
}

# Exit message
if ($Mode -ne "Help" -and $Mode -ne "Continuous") {
    Write-Host "`n" -NoNewline
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "Process completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host ("=" * 60) -ForegroundColor Cyan
}
