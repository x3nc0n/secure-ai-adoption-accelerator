<#
.SYNOPSIS
    Removes Microsoft Sentinel - AI Governance Solution artifacts from a target
    resource group and verifies clean removal.

.DESCRIPTION
    Removal and cleanup script for AIGS validation environments.
    Removes deployed Logic App resources and their API connections.
    Does NOT remove:
      - The Log Analytics workspace or Sentinel instance
      - The UAMI or its role assignments (UAMI lifecycle is independent of solution)
      - Watchlists (these are Sentinel-side resources; remove via Sentinel UI or API if needed)

    Verifies that no orphaned Logic App or connection resources remain after removal.
    Safe to run idempotently — missing resources are reported as "already removed."

.PARAMETER TenantId
    Azure AD tenant ID for the target environment.

.PARAMETER SubscriptionId
    Subscription ID for the target resource group.

.PARAMETER ResourceGroupName
    Resource group containing the deployed AIGS Logic App resources.

.PARAMETER WhatIf
    Dry-run mode. Lists resources that would be removed without deleting them.

.EXAMPLE
    .\Remove-AIGovernanceValidation.ps1 `
        -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
        -SubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
        -ResourceGroupName "rg-aigs-validation" `
        -WhatIf

.NOTES
    Author:  x3nc0n / Tank (Automation Engineer)
    Version: 0.1.0-preview.1
    Date:    2026-07-17

    UAMI role assignments are NOT removed by this script.
    Watchlist cleanup: use Sentinel Content Hub uninstall or the Watchlists API.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step { param([int]$N, [string]$M) Write-Host "`n─── Step ${N}: $M ───" -ForegroundColor Cyan }
function Write-Ok   { param([string]$M) Write-Host "  ✅ $M" -ForegroundColor Green }
function Write-Skip { param([string]$M) Write-Host "  ⏭  $M" -ForegroundColor Yellow }
function Write-Info { param([string]$M) Write-Host "  ℹ  $M" -ForegroundColor White }
function Write-Fail { param([string]$M) Write-Host "  ❌ $M" -ForegroundColor Red }

# ─── Step 1: Verify login context ────────────────────────────────────────────
Write-Step 1 "Verify login context"
$context = Get-AzContext -ErrorAction Stop
if (-not $context -or $context.Tenant.Id -ne $TenantId) {
    Write-Fail "Tenant mismatch. Expected: $TenantId, Got: $($context.Tenant.Id)"
    exit 1
}
if ($context.Subscription.Id -ne $SubscriptionId) {
    Write-Fail "Subscription mismatch. Expected: $SubscriptionId, Got: $($context.Subscription.Id)"
    exit 1
}
Write-Ok "Login context verified."

# ─── Step 2: Verify resource group ────────────────────────────────────────────
Write-Step 2 "Verify resource group"
$rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if (-not $rg) {
    Write-Skip "Resource group '$ResourceGroupName' not found — nothing to remove."
    exit 0
}
Write-Ok "Resource group '$ResourceGroupName' found."

# ─── Resources to remove ──────────────────────────────────────────────────────
# Logic Apps (playbooks)
$logicApps = @(
    'AIGS-Notify-001-TeamsAlert',
    'AIGS-Auto-001-RestoreDiagnostics'
)

# API connections (naming convention: <connectorName>-<playbookName>)
$connections = @(
    'azuresentinel-AIGS-Notify-001-TeamsAlert',
    'teams-AIGS-Notify-001-TeamsAlert',
    'azuresentinel-AIGS-Auto-001-RestoreDiagnostics',
    'teams-AIGS-Auto-001-RestoreDiagnostics',
    'arm-AIGS-Auto-001-RestoreDiagnostics'
)

# ─── Step 3: Remove Logic Apps ────────────────────────────────────────────────
Write-Step 3 "Remove Logic Apps (playbooks)"
foreach ($la in $logicApps) {
    $resource = Get-AzResource `
        -ResourceGroupName $ResourceGroupName `
        -Name $la `
        -ResourceType "Microsoft.Logic/workflows" `
        -ErrorAction SilentlyContinue

    if ($resource) {
        Write-Info "Removing Logic App: $la"
        if ($PSCmdlet.ShouldProcess("$ResourceGroupName/$la", "Remove Logic App")) {
            Remove-AzResource -ResourceId $resource.ResourceId -Force | Out-Null
            Write-Ok "Removed Logic App: $la"
        }
    } else {
        Write-Skip "Logic App not found (already removed): $la"
    }
}

# ─── Step 4: Remove API connections ──────────────────────────────────────────
Write-Step 4 "Remove API connections"
foreach ($conn in $connections) {
    $resource = Get-AzResource `
        -ResourceGroupName $ResourceGroupName `
        -Name $conn `
        -ResourceType "Microsoft.Web/connections" `
        -ErrorAction SilentlyContinue

    if ($resource) {
        Write-Info "Removing API connection: $conn"
        if ($PSCmdlet.ShouldProcess("$ResourceGroupName/$conn", "Remove API Connection")) {
            Remove-AzResource -ResourceId $resource.ResourceId -Force | Out-Null
            Write-Ok "Removed connection: $conn"
        }
    } else {
        Write-Skip "Connection not found (already removed): $conn"
    }
}

# ─── Step 5: Verify clean removal ─────────────────────────────────────────────
if (-not $WhatIf) {
    Write-Step 5 "Verify clean removal"
    $orphans = @()

    foreach ($la in $logicApps) {
        $r = Get-AzResource -ResourceGroupName $ResourceGroupName -Name $la -ResourceType "Microsoft.Logic/workflows" -ErrorAction SilentlyContinue
        if ($r) { $orphans += "Logic App: $la" }
    }
    foreach ($conn in $connections) {
        $r = Get-AzResource -ResourceGroupName $ResourceGroupName -Name $conn -ResourceType "Microsoft.Web/connections" -ErrorAction SilentlyContinue
        if ($r) { $orphans += "Connection: $conn" }
    }

    if ($orphans.Count -gt 0) {
        Write-Fail "Orphaned resources remain after removal:"
        foreach ($o in $orphans) { Write-Info "  $o" }
        exit 1
    }
    Write-Ok "Clean removal verified. No orphaned AIGS resources remain in '$ResourceGroupName'."
}

# ─── Final summary ────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "══════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  AIGS Removal Complete ✅" -ForegroundColor Green
Write-Host "══════════════════════════════════════════════════" -ForegroundColor Green
Write-Info "Resource Group: $ResourceGroupName"
Write-Info ""
Write-Info "Resources NOT removed by this script (by design):"
Write-Info "  - UAMI and its role assignments (independent lifecycle)"
Write-Info "  - Log Analytics workspace / Sentinel instance"
Write-Info "  - Sentinel Watchlists (remove via Sentinel Content Hub or Watchlists API)"
Write-Info ""
if ($WhatIf) {
    Write-Host "[DRY RUN] No resources were removed." -ForegroundColor Yellow
}
