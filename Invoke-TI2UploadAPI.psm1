# Invoke-TI2UploadAPI.ps1
# PowerShell function to fetch indicators from Mock TI API and upload to Microsoft Sentinel
# Based on Microsoft documentation: https://learn.microsoft.com/en-us/azure/sentinel/stix-objects-api

function Invoke-TI2UploadAPI {
<#
.SYNOPSIS
    Fetches STIX indicators from Mock TI API and uploads them to Microsoft Sentinel Threat Intelligence API
    
.DESCRIPTION
    This function connects to a mock TI API endpoint to retrieve STIX indicators,
    then uploads them to Microsoft Sentinel using the TI Upload API (Preview).
    Handles pagination for both fetching and uploading (max 100 indicators per upload).
    
.PARAMETER EnvFile
    Path to the .env file containing Azure credentials. Defaults to .\.env
    
.PARAMETER MockApiUrl
    Base URL of the Mock TI API. Defaults to http://mock-ti-api:8000

.PARAMETER ApiKey
    API Key for the Mock TI API. If not provided, will try to read from .env file
    
.PARAMETER MaxIndicatorsPerUpload
    Maximum number of indicators to upload per batch to Sentinel (max 100). Defaults to 100
    
.PARAMETER ShowProgress
    If specified, displays detailed progress information
    
.PARAMETER TestMode
    If specified, fetches indicators but doesn't upload to Sentinel (dry run)
    
.PARAMETER SaveToFile
    If specified, saves fetched indicators to a JSON file for debugging
    
.EXAMPLE
    Invoke-TI2UploadAPI
    
.EXAMPLE
    Invoke-TI2UploadAPI -MockApiUrl "http://mock-ti-api:8000" -ShowProgress
    
.EXAMPLE
    Invoke-TI2UploadAPI -TestMode -SaveToFile
    
.NOTES
    Requires: PowerShell 5.1 or higher
    API Documentation: https://learn.microsoft.com/en-us/azure/sentinel/stix-objects-api
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$EnvFile = "/app/config/.env",
        
        [Parameter(Mandatory = $false)]
        [string]$MockApiUrl = "http://mock-ti-api:8080",

        [Parameter(Mandatory = $false)]
        [string]$ApiKey,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 100)]
        [int]$MaxIndicatorsPerUpload = 100,
        
        [Parameter(Mandatory = $false)]
        [switch]$ShowProgress,
        
        [Parameter(Mandatory = $false)]
        [switch]$TestMode,
        
        [Parameter(Mandatory = $false)]
        [switch]$SaveToFile
    )

    # Helper function to mask sensitive values
    
    function Mask-SensitiveValue {
        param (
            [string]$Value
        )

        if ($Value.Length -le 7) {
            return $Value
        }

        $firstPart = $Value.Substring(0,3)
        $lastPart = $Value.Substring($Value.Length - 4)
        $middle = $Value.Substring(3, $Value.Length - 7)

        # Replace all non-dash characters in the middle with '*'
        $maskedMiddle = ($middle.ToCharArray() | ForEach-Object {
            if ($_ -eq '-') { '-' } else { '*' }
        }) -join ''

        return "$firstPart$maskedMiddle$lastPart"
    }


    # Helper function to read .env file
    function Read-EnvFile {
        param ([string]$Path)
        
        $envVars = @{}
        
        if (Test-Path $Path) {
            Get-Content $Path | ForEach-Object {
                if ($_ -match '^([^#][^=]+)=(.*)$') {
                    $key = $matches[1].Trim()
                    $value = $matches[2].Trim()
                    # Remove quotes if present
                    $value = $value -replace '^["'']|["'']$', ''
                    $envVars[$key] = $value
                }
            }
        } else {
            Write-Error "Environment file not found: $Path"
            return $null
        }
        
        return $envVars
    }

    # Helper function to get access token using client secret
    function Get-AzureTokenWithSecret {
        param (
            [string]$TenantId,
            [string]$ClientId,
            [string]$ClientSecret,
            [string]$Scope,
            [string]$AuthorityUrl
        )
        
        $tokenEndpoint = "$AuthorityUrl/$TenantId/oauth2/v2.0/token"
        
        $body = @{
            grant_type    = "client_credentials"
            client_id     = $ClientId
            client_secret = $ClientSecret
            scope         = $Scope
        }
        
        try {
            $response = Invoke-RestMethod -Uri $tokenEndpoint -Method POST -Body $body -ContentType "application/x-www-form-urlencoded"
            return $response.access_token
        } catch {
            Write-Error "Failed to acquire token: $_"
            return $null
        }
    }

    # Helper function to fetch indicators from Mock API
    function Get-MockApiTIIndicators {
        param (
            [string]$BaseUrl,
            [string]$ApiKey,
            [switch]$ShowProgress
        )
        
        $indicatorsUrl = "$BaseUrl/api/v1/indicators"
        $healthUrl = "$BaseUrl/healthz"
        
        # Check API health first
        if ($ShowProgress) {
            Write-Host "Checking Mock API health..." -ForegroundColor Gray
        }
        
        try {
            $headers = @{}
            if ($ApiKey) {
                $headers["X-API-Key"] = $ApiKey
            }

            $healthResponse = Invoke-RestMethod -Uri $healthUrl -Method GET -Headers $headers -ContentType "application/json"
            if ($healthResponse.status -eq "ok") {
                Write-Host "✓ [Get-MockApiTIIndicators] Mock API is healthy" -ForegroundColor Green
            }
        } catch {
            Write-Warning "[Get-MockApiTIIndicators] Mock API health check failed: $_"
        }
        
        # Fetch indicators
        if ($ShowProgress) {
            Write-Host "[Get-MockApiTIIndicators] Fetching indicators from Mock API..." -ForegroundColor Gray
        }
        
        try {
            $response = Invoke-RestMethod -Uri $indicatorsUrl -Method GET -Headers $headers -ContentType "application/json"

            if ($response.stixobjects) {
                Write-Host "✓ [Get-MockApiTIIndicators] Fetched $($response.stixobjects.Count) indicators from Mock API" -ForegroundColor Green
                if ($ShowProgress -and $response.sourcesystem) {
                    Write-Host "  Source System: $($response.sourcesystem)" -ForegroundColor Gray
                }
                return $response
            } else {
                Write-Error "[Get-MockApiTIIndicators] No indicators found in API response"
                return $null
            }
        } catch {
            Write-Error "[Get-MockApiTIIndicators] Failed to fetch indicators from Mock API: $_"
            return $null
        }
    }

    # Main execution starts here
    Write-Host "=" -ForegroundColor Cyan -NoNewline
    Write-Host ("=" * 59) -ForegroundColor Cyan
    Write-Host "SC.AI X-GEN TI API to Microsoft Sentinel (API TI Upload)" -ForegroundColor Yellow
    Write-Host ("=" * 60) -ForegroundColor Cyan

    # Read environment variables
    Write-Host "`nReading configuration from: $EnvFile" -ForegroundColor Gray
    $env = Read-EnvFile -Path $EnvFile
    
    if (-not $env) {
        Write-Error "Failed to read environment file"
        return
    }

    # Extract Azure credentials
    $clientId = $env["AZURE_CLIENT_ID"]
    $clientSecret = $env["AZURE_CLIENT_SECRET"]
    $tenantId = $env["AZURE_TENANT_ID"]
    $workspaceId = $env["AZURE_WORKSPACE_ID"]
    $azureCloud = if ($env["AZURE_CLOUD"]) { $env["AZURE_CLOUD"].ToUpper() } else { "AzureCloud" }
    
    # Use API key from parameter or environment
    if (-not $ApiKey) {
        $ApiKey = $env["API_KEYS"]
    }

    # Validate required variables
    $missingVars = @()
    if (-not $clientId) { $missingVars += "AZURE_CLIENT_ID" }
    if (-not $clientSecret) { $missingVars += "AZURE_CLIENT_SECRET" }
    if (-not $tenantId) { $missingVars += "AZURE_TENANT_ID" }
    if (-not $workspaceId) { $missingVars += "AZURE_WORKSPACE_ID" }
    
    if ($missingVars.Count -gt 0) {
        Write-Error "Missing required environment variables: $($missingVars -join ', ')"
        return
    }

    # Display configuration
    Write-Host "`nConfiguration:" -ForegroundColor Yellow
    Write-Host ("✓ SC.AI TI API URI:     {0}" -f $MockApiUrl) -ForegroundColor White
    Write-Host ("✓ Azure Cloud:          {0}" -f $azureCloud) -ForegroundColor White
    Write-Host ("✓ Tenant ID:            {0}" -f (Mask-SensitiveValue $tenantId)) -ForegroundColor White
    Write-Host ("✓ Log-A Workspace ID:   {0}" -f (Mask-SensitiveValue $workspaceId)) -ForegroundColor White
    Write-Host ("✓ Max IOC's per upload: {0}" -f $MaxIndicatorsPerUpload) -ForegroundColor White

    if ($TestMode) {
        Write-Host "✓ Mode: TEST MODE (no upload)" -ForegroundColor Yellow
    }

    # Step 1: Fetch indicators from Mock API
    Write-Host "`n" -NoNewline
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "Step 1: Fetching Indicators from Mock API" -ForegroundColor Yellow
    Write-Host ("=" * 60) -ForegroundColor Cyan

    $apiResponse = Get-MockApiTIIndicators -BaseUrl $MockApiUrl -ApiKey $ApiKey -ShowProgress:$ShowProgress

    if ($ShowProgress) {
        Write-Host "DEBUG: Response type: $($apiResponse.GetType().Name)"
        Write-Host "DEBUG: StixObjects type: $($apiResponse.stixobjects.GetType().Name)"
        Write-Host "DEBUG: SourceSystem: $($apiResponse.sourcesystem)"
        Write-Host "DEBUG: StixObjects count: $($apiResponse.stixobjects.Count)"
        Write-Host "DEBUG: First object: $($apiResponse.stixobjects[0] | ConvertTo-Json -Compress)"
    }

    # DEBUGGING - Lorenzo (FIXED: Now properly converts to JSON)
    # $apiResponse | ConvertTo-Json -Depth 10 | Out-File -FilePath ".\logs\MockAPI_TI_$(Get-Date -Format 'yyyyMMdd_HHmmss').json" -Encoding UTF8

    Write-Host "✓ [Invoke-TI2UploadAPI] Fetched $($apiResponse.stixobjects.Count) indicators from Mock API" -ForegroundColor Green

    if (-not $apiResponse -or -not $apiResponse.stixobjects) {
        Write-Error "Failed to fetch indicators from Mock API"
        return
    }
    
    # FIXED: Ensure stixObjects is properly handled as an array
    $stixObjects = @($apiResponse.stixobjects)
    $sourceSystem = $apiResponse.sourcesystem
    $totalIndicators = $stixObjects.Count

    # Debug array handling
    if ($ShowProgress) {
        Write-Host "DEBUG: StixObjects is array: $($stixObjects -is [array])"
        Write-Host "DEBUG: StixObjects type after conversion: $($stixObjects.GetType().FullName)"
        Write-Host "DEBUG: Total indicators to process: $totalIndicators"
    }

    Write-Host "`nIndicator Summary:" -ForegroundColor Yellow
    $summary = $stixObjects | Group-Object -Property type | Select-Object Name, Count
    foreach ($item in $summary) {
        Write-Host "  $($item.Name): $($item.Count)" -ForegroundColor White
    }
    
    # Save to file if requested
    if ($SaveToFile) {
        $outputFile = ".\MockAPI_TI_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
        $apiResponse | ConvertTo-Json -Depth 10 | Set-Content -Path $outputFile -Encoding UTF8
        Write-Host "`n✓ Saved indicators to: $outputFile" -ForegroundColor Green
    }
    
    # Exit if in test mode
    if ($TestMode) {
        Write-Host "`n✓ Test mode complete - no upload performed" -ForegroundColor Yellow
        return $apiResponse
    }

    # Step 2: Prepare for upload to Sentinel
    Write-Host "`n" -NoNewline
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "Step 2: Uploading to Microsoft Sentinel" -ForegroundColor Yellow
    Write-Host ("=" * 60) -ForegroundColor Cyan

    # Pull ResourceUrl & AD Authority from Environment via (Get-AzContext).Environment
    # If Get-AzContext is not available, use defaults based on cloud
    try {
        $azEnv = (Get-AzContext).Environment
        $authorityUrl = $azEnv.ActiveDirectoryAuthority
        $scope = $azEnv.ResourceManagerUrl + ".default"
    } catch {
        # Fallback to defaults if Az module is not available
        if ($azureCloud -eq "AzureUSGovernment") {
            $authorityUrl = "https://login.microsoftonline.us"
            $scope = "https://management.usgovcloudapi.net/.default"
        } elseif ($azureCloud -eq "AzureCloud") {
            $authorityUrl = "https://login.microsoftonline.com"
            $scope = "https://management.azure.com/.default"
        } else {
            throw "Unsupported Azure Cloud: $azureCloud. Supported values are 'AzureCloud' or 'AzureUSGovernment'."
        }
    }

    # Acquire Azure token
    Write-Host "`n[Invoke-TI2UploadAPI] Acquiring Azure access token..." -ForegroundColor Gray
    $token = Get-AzureTokenWithSecret -TenantId $tenantId -ClientId $clientId -ClientSecret $clientSecret -Scope $scope -AuthorityUrl $authorityUrl
    
    if (-not $token) {
        Write-Error "[Invoke-TI2UploadAPI] Failed to acquire access token"
        return
    }

    Write-Host "✓ [Invoke-TI2UploadAPI] Token acquired successfully" -ForegroundColor Green

    # Prepare headers for Sentinel API
    $headers = @{
        "Authorization" = "Bearer $token"
        "Content-Type"  = "application/json"
    }

    # Sentinel TI Upload API endpoint (Preview)
    $sentinelUploadUrl = "https://api.ti.sentinel.azure.com/workspaces/$($workspaceId)/threat-intelligence-stix-objects:upload?api-version=2024-02-01-preview"

    
    # Use [System.Uri] to parse and extract the base URI
    $uri = [System.Uri]$sentinelUploadUrl
    $BaseUri = "$($uri.Scheme)://$($uri.Host)"

    # Split indicators into batches (max 100 per upload)
    Write-Host "`nPreparing batches for upload (max $MaxIndicatorsPerUpload indicators per batch)..." -ForegroundColor Cyan
    
    # Simple batching logic that works correctly
    $batches = @()
    $batchSize = $MaxIndicatorsPerUpload
    
    for ($i = 0; $i -lt $totalIndicators; $i += $batchSize) {
        $endIndex = [Math]::Min($i + $batchSize, $totalIndicators)
        $batch = $stixObjects[$i..($endIndex - 1)]
        $batches += ,@($batch)  # Use unary comma operator to ensure array of arrays
    }
    
    $batchCount = $batches.Count
    
    Write-Host "Will upload $totalIndicators indicators in $batchCount batch(es)..." -ForegroundColor Cyan
    
    # Verify batch sizes
    for ($idx = 0; $idx -lt $batches.Count; $idx++) {
        $currentBatchSize = $batches[$idx].Count
        Write-Host "  Batch $($idx + 1): $currentBatchSize indicators" -ForegroundColor Gray
    }

    $successfulUploads = 0
    $failedUploads = 0
    $uploadedIndicators = 0
    
    for ($i = 0; $i -lt $batchCount; $i++) {
        $batch = $batches[$i]
        $batchNumber = $i + 1
        
        # Ensure batch is an array and get its count
        if ($batch -isnot [System.Array]) {
            $batch = @($batch)
        }
        $batchSize = $batch.Count

        Write-Host "`n[Invoke-TI2UploadAPI] Batch $batchNumber/$batchCount ($batchSize indicators):" -ForegroundColor Yellow

        # Prepare request body with the batch and REQUIRED FIELDS!
        # https://learn.microsoft.com/en-us/azure/sentinel/stix-objects-api
        # REQUIRED FIELD: sourcesystem
        # REQUIRED FIELD: stixobjects
        # Ensure batch is properly formatted as an array
        $requestBody = @{
            sourcesystem = $sourceSystem
            stixobjects = @($batch)
        }

        # Debug output to see what's being sent
        if ($ShowProgress) {
            Write-Host "DEBUG: Batch content:"
            Write-Host ($batch | ConvertTo-Json -Depth 5 -Compress)
            Write-Host "DEBUG: Request body structure:"
            Write-Host ($requestBody | ConvertTo-Json -Depth 5 -Compress)
        }

        try {
            # FIXED: Properly convert to JSON before sending
            $bodyJson = $requestBody | ConvertTo-Json -Depth 10 -Compress
            
            if ($ShowProgress) {
                Write-Host "DEBUG: SENTINEL REST API: $sentinelUploadUrl"
                Write-Host "[Invoke-TI2UploadAPI]  Uploading..." -ForegroundColor Gray
                Write-Host "DEBUG: JSON being sent (first 500 chars): $($bodyJson.Substring(0, [Math]::Min(500, $bodyJson.Length)))" -ForegroundColor Magenta
            }
            
            Write-Host ("✓ Entra ID::Tenant ID:        {0}" -f (Mask-SensitiveValue $tenantId))
            Write-Host ("✓ Entra ID::Application ID:   {0}" -f (Mask-SensitiveValue $clientId))
            Write-Host ("✓ Entra ID::Client Secret:    {0}" -f (Mask-SensitiveValue $clientSecret))
            Write-Host ("✓ Sentinel TI Upload API URI: {0}" -f $BaseUri)
            
            # FIXED: Pass JSON string to Body parameter, not the hashtable
            $response = Invoke-RestMethod -Uri $sentinelUploadUrl -Headers $headers -Body $bodyJson -Method POST -ContentType "application/json"

            Write-Host "`n✓ Batch $batchNumber uploaded successfully" -ForegroundColor Green
            $successfulUploads++
            $uploadedIndicators += $batchSize
            
            if ($ShowProgress -and $response) {
                Write-Host "  Response: $($response | ConvertTo-Json -Compress)" -ForegroundColor Gray
            }
            
            # Add a small delay between batches to avoid rate limiting
            if ($i -lt $batchCount - 1) {
                Start-Sleep -Milliseconds 500
            }
            
        } catch {
            $failedUploads++
            $statusCode = $_.Exception.Response.StatusCode.value__
            $statusDescription = $_.Exception.Response.StatusDescription

            Write-Host "  ✗ [Invoke-TI2UploadAPI] Batch $batchNumber failed" -ForegroundColor Red

            if ($statusCode) {
                Write-Host "   Status: $statusCode - $statusDescription" -ForegroundColor Red
            }

            Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red

            # FIXED: Always try to get error details, not just when ShowProgress is on
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $responseBody = $reader.ReadToEnd()
                Write-Host "  [Invoke-TI2UploadAPI] API Error Details: $responseBody" -ForegroundColor Red
            } catch {
                Write-Host "  [Invoke-TI2UploadAPI] Could not read error response body" -ForegroundColor Gray
            }
        }
    }
    
    # Final summary
    Write-Host "`n" -NoNewline
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "Upload Summary" -ForegroundColor Yellow
    Write-Host ("=" * 60) -ForegroundColor Cyan

    if ($successfulUploads -eq $batchCount) {
        Write-Host "✓ All batches uploaded successfully!" -ForegroundColor Green
    } elseif ($successfulUploads -gt 0) {
        Write-Host "⚠ Partial success" -ForegroundColor Yellow
    } else {
        Write-Host "✗ All uploads failed" -ForegroundColor Red
    }

    Write-Host "`nStatistics:" -ForegroundColor Yellow
    Write-Host "  Total Indicators: $totalIndicators" -ForegroundColor White
    Write-Host "  Uploaded Indicators: $uploadedIndicators" -ForegroundColor White
    Write-Host "  Successful Batches: $successfulUploads/$batchCount" -ForegroundColor White
    if ($failedUploads -gt 0) {
        Write-Host "  Failed Batches: $failedUploads" -ForegroundColor Red
    }

    Write-Host "`n✓ Sentinel TI API Upload process completed!" -ForegroundColor Green

    # Return summary object
    return @{
        TotalIndicators = $totalIndicators
        UploadedIndicators = $uploadedIndicators
        SuccessfulBatches = $successfulUploads
        FailedBatches = $failedUploads
        SourceSystem = $sourceSystem
    }
}

# Export the function
Export-ModuleMember -Function Invoke-TI2UploadAPI
