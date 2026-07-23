<#
.SYNOPSIS
    Syncs rawContent in watchlist ARM templates from their paired CSV files.

.DESCRIPTION
    Reads each watchlist CSV, validates required columns, normalizes line endings to LF,
    and writes the normalized content into the rawContent field of the paired ARM template.
    Errors and exits non-zero if any schema mismatch is detected.

.PARAMETER SolutionRoot
    Root of the repository. Defaults to the parent of the scripts/ directory.

.EXAMPLE
    .\Sync-AIGovernanceWatchlists.ps1
    .\Sync-AIGovernanceWatchlists.ps1 -SolutionRoot "C:\repo\secure-ai-adotpion-accelerator"
#>
param(
    [string]$SolutionRoot = (Resolve-Path "$PSScriptRoot\..").Path
)

$ErrorActionPreference = 'Stop'

$watchlists = @(
    @{
        Name            = 'AIGS_ContentFilterPolicies'
        RequiredColumns = @(
            'ItemKey', 'PolicyName', 'ResourceId', 'AccountName', 'SubscriptionId',
            'HateSeverityThreshold', 'ViolenceSeverityThreshold', 'SelfHarmSeverityThreshold',
            'SexualSeverityThreshold', 'JailbreakEnabled', 'IndirectAttackEnabled',
            'Status', 'BaselineVersion', 'LastUpdated'
        )
    },
    @{
        Name            = 'AIGS_ApprovedModels'
        RequiredColumns = @(
            'ItemKey', 'ModelId', 'DeploymentName', 'AccountName', 'ResourceGroupName',
            'SubscriptionId', 'ApprovedVersion', 'MaxCapacityTPM', 'Region',
            'Status', 'BaselineVersion', 'LastUpdated'
        )
    }
)

$errorCount = 0
$solutionPath = Join-Path $SolutionRoot 'Solutions\Microsoft Sentinel - AI Governance Solution'

foreach ($wl in $watchlists) {
    $dir      = Join-Path $solutionPath "Watchlists\$($wl.Name)"
    $csvPath  = Join-Path $dir "$($wl.Name).csv"
    $jsonPath = Join-Path $dir "$($wl.Name).json"

    if (-not (Test-Path $csvPath)) {
        Write-Error "[$($wl.Name)] CSV not found: $csvPath"
        $errorCount++
        continue
    }
    if (-not (Test-Path $jsonPath)) {
        Write-Error "[$($wl.Name)] JSON not found: $jsonPath"
        $errorCount++
        continue
    }

    # Validate schema: first line must have all required columns
    $headerLine = (Get-Content $csvPath -TotalCount 1).TrimEnd("`r")
    $actualCols = $headerLine -split ','

    foreach ($col in $wl.RequiredColumns) {
        if ($col -notin $actualCols) {
            Write-Error "[$($wl.Name)] Schema mismatch: missing required column '$col'. Header: $headerLine"
            $errorCount++
        }
    }

    # ItemKey must be the first column
    if ($actualCols[0] -ne 'ItemKey') {
        Write-Error "[$($wl.Name)] Schema mismatch: first column must be 'ItemKey', got '$($actualCols[0])'."
        $errorCount++
    }

    if ($errorCount -gt 0) { continue }

    # Normalize to LF, strip trailing newline
    $normalized = (Get-Content $csvPath -Raw).Replace("`r`n", "`n").Replace("`r", "`n").TrimEnd("`n")

    # Read and update the ARM template
    $template = Get-Content $jsonPath -Raw | ConvertFrom-Json

    if ($null -eq $template.resources -or $template.resources.Count -eq 0) {
        Write-Error "[$($wl.Name)] ARM template has no resources array in $jsonPath"
        $errorCount++
        continue
    }

    if ($null -eq $template.resources[0].properties) {
        Write-Error "[$($wl.Name)] resources[0] has no properties object in $jsonPath"
        $errorCount++
        continue
    }

    $template.resources[0].properties.rawContent = $normalized

    $updated = $template | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($jsonPath, $updated, [System.Text.Encoding]::UTF8)

    Write-Host "[$($wl.Name)] rawContent synced ($($normalized.Length) chars from $csvPath)"
}

if ($errorCount -gt 0) {
    Write-Error "Sync completed with $errorCount error(s). Fix schema mismatches before proceeding."
    exit 1
}

Write-Host 'All watchlists synced successfully.'
