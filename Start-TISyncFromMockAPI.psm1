# Start-TISyncFromMockAPI.ps1
# PowerShell function to continuously sync indicators from Mock API to Microsoft Sentinel

function Start-TISyncFromMockAPI {
<#
.SYNOPSIS
    Continuously syncs indicators from Mock API to Microsoft Sentinel
    
.DESCRIPTION
    Runs the TI upload process on a schedule, fetching from Mock API and uploading to Sentinel.
    Requires the Invoke-TI2UploadAPI function to be loaded.
    
.PARAMETER IntervalMinutes
    Interval between sync operations in minutes. Defaults to 180
    
.PARAMETER EnvFile
    Path to the .env file containing configuration
    
.PARAMETER MockApiUrl
    Base URL of the Mock TI API
    
.PARAMETER RunOnce
    If specified, runs only once instead of continuously
    
.PARAMETER ShowProgress
    If specified, shows detailed progress during sync operations
    
.EXAMPLE
    Start-TISyncFromMockAPI -IntervalMinutes 30
    
.EXAMPLE
    Start-TISyncFromMockAPI -RunOnce
    
.EXAMPLE
    Start-TISyncFromMockAPI -IntervalMinutes 60 -ShowProgress
    
.NOTES
    Requires: Invoke-TI2UploadAPI function to be loaded
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [int]$IntervalMinutes = 120,
        
        [Parameter(Mandatory = $false)]
        [string]$EnvFile = "/app/config/.env",

        [Parameter(Mandatory = $false)]
        [string]$MockApiUrl = "http://mock-ti-api:8080",
        
        [Parameter(Mandatory = $false)]
        [switch]$RunOnce,
        
        [Parameter(Mandatory = $false)]
        [switch]$ShowProgress
    )
    
    # Check if Invoke-TI2UploadAPI is available
    if (-not (Get-Command Invoke-TI2UploadAPI -ErrorAction SilentlyContinue)) {
        Write-Error "Invoke-TI2UploadAPI function not found. Please load Invoke-TI2UploadAPI.ps1 first."
        return
    }
    
    Write-Host "=" -ForegroundColor Cyan -NoNewline
    Write-Host ("=" * 59) -ForegroundColor Cyan
    Write-Host "TI Sync Service - Mock API to Sentinel" -ForegroundColor Yellow
    Write-Host ("=" * 60) -ForegroundColor Cyan
    
    if ($RunOnce) {
        Write-Host "`nRunning single sync operation..." -ForegroundColor Yellow
        $result = Invoke-TI2UploadAPI -EnvFile $EnvFile -MockApiUrl $MockApiUrl -ShowProgress:$ShowProgress
        
        if ($result -and $result.SuccessfulBatches -gt 0) {
            Write-Host "`n✓ Sync completed successfully" -ForegroundColor Green
            Write-Host "  Uploaded: $($result.UploadedIndicators) indicators" -ForegroundColor Gray
        } else {
            Write-Host "`n✗ Sync failed" -ForegroundColor Red
        }
        
        return $result
    }
    
    Write-Host "`nStarting continuous sync service" -ForegroundColor Yellow
    Write-Host "  Sync Interval: Every $IntervalMinutes minutes" -ForegroundColor Gray
    Write-Host "  Mock API URL: $MockApiUrl" -ForegroundColor Gray
    Write-Host "  Show Progress: $ShowProgress" -ForegroundColor Gray
    Write-Host "`nPress Ctrl+C to stop" -ForegroundColor DarkGray
    
    $cycleCount = 0
    $lastSuccessTime = $null
    $totalUploaded = 0
    $consecutiveFailures = 0
    $maxConsecutiveFailures = 5
    
    # Register cleanup on Ctrl+C
    [Console]::TreatControlCAsInput = $false
    
    while ($true) {
        $cycleCount++
        $syncTime = Get-Date
        
        Write-Host "`n" -NoNewline
        Write-Host ("=" * 60) -ForegroundColor Cyan
        Write-Host "SYNC CYCLE #$cycleCount - $($syncTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Yellow
        Write-Host ("=" * 60) -ForegroundColor Cyan
        
        try {
            $result = Invoke-TI2UploadAPI -EnvFile $EnvFile -MockApiUrl $MockApiUrl -ShowProgress:$ShowProgress
            Write-Output "Invoke-TI2UploadAPI Result: $($result | Out-String)"
            if ($result -and $result.SuccessfulBatches -gt 0) {
                $lastSuccessTime = $syncTime
                $totalUploaded += $result.UploadedIndicators
                $consecutiveFailures = 0
                
                Write-Host "`n✓ Cycle #$cycleCount completed successfully" -ForegroundColor Green
                Write-Host "  Uploaded: $($result.UploadedIndicators) indicators" -ForegroundColor Gray
                Write-Host "  Source: $($result.SourceSystem)" -ForegroundColor Gray
            } else {
                $consecutiveFailures++
                Write-Host "`n⚠ Cycle #$cycleCount completed with errors" -ForegroundColor Yellow
                Write-Host "  Consecutive failures: $consecutiveFailures" -ForegroundColor Yellow
            }
            
            # Display running statistics
            Write-Host "`nRunning Statistics:" -ForegroundColor Cyan
            Write-Host "  Total Cycles: $cycleCount" -ForegroundColor White
            Write-Host "  Total Uploaded: $totalUploaded indicators" -ForegroundColor White
            if ($lastSuccessTime) {
                Write-Host "  Last Success: $($lastSuccessTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White
            }
            Write-Host "  Consecutive Failures: $consecutiveFailures" -ForegroundColor $(if ($consecutiveFailures -gt 0) { "Yellow" } else { "White" })
            
            # Check for too many consecutive failures
            if ($consecutiveFailures -ge $maxConsecutiveFailures) {
                Write-Host "`n✗ Too many consecutive failures ($maxConsecutiveFailures). Stopping sync service." -ForegroundColor Red
                Write-Host "Please check:" -ForegroundColor Yellow
                Write-Host "  - Mock API availability at $MockApiUrl" -ForegroundColor Gray
                Write-Host "  - Azure credentials in $EnvFile" -ForegroundColor Gray
                Write-Host "  - Network connectivity" -ForegroundColor Gray
                break
            }
            
        } catch {
            $consecutiveFailures++
            Write-Error "Sync cycle failed: $_"
            
            if ($consecutiveFailures -ge $maxConsecutiveFailures) {
                Write-Host "`n✗ Critical error after $maxConsecutiveFailures attempts. Stopping." -ForegroundColor Red
                break
            }
        }
        
        # Calculate next run time
        $nextRun = (Get-Date).AddMinutes($IntervalMinutes)
        Write-Host "`nNext sync scheduled for: $($nextRun.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Cyan
        Write-Host "Waiting $IntervalMinutes minutes... (Press Ctrl+C to stop)" -ForegroundColor Gray
        
        # Sleep with ability to interrupt
        try {
            Start-Sleep -Seconds ($IntervalMinutes * 60)
        } catch {
            Write-Host "`nSync service interrupted by user" -ForegroundColor Yellow
            break
        }
    }
    
    # Final statistics
    Write-Host "`n" -NoNewline
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "Sync Service Stopped" -ForegroundColor Yellow
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "Final Statistics:" -ForegroundColor Cyan
    Write-Host "  Total Cycles Run: $cycleCount" -ForegroundColor White
    Write-Host "  Total Indicators Uploaded: $totalUploaded" -ForegroundColor White
    if ($lastSuccessTime) {
        Write-Host "  Last Successful Sync: $($lastSuccessTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White
    }
}

# Export the function
Export-ModuleMember -Function Start-TISyncFromMockAPI
