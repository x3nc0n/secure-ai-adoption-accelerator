<#
.SYNOPSIS
    Creates or accepts a User-Assigned Managed Identity (UAMI) and assigns narrowly scoped
    RBAC roles required by AIGS playbooks.

.DESCRIPTION
    Bootstrap script for Microsoft Sentinel - AI Governance Solution UAMI setup.
    Supports WhatIf/dry-run. Never hard-codes tenant, subscription, resource group,
    workspace, or identity values. All values are required as parameters.

    Role assignments are additive — existing assignments are not removed.
    The script checks for existing assignments and skips duplicates.

    UAMI roles assigned:
        PB-NOTIFY-01 (Sentinel notification):
            - Microsoft Sentinel Reader on the Sentinel workspace resource
        PB-AUTO-01 (diagnostic settings restore):
            - Microsoft Sentinel Responder on the Sentinel workspace resource
            - Monitoring Contributor on the target remediation resource group

    A single shared UAMI is optional — use -SharedUami to consolidate roles on one identity.
    If separate UAMIs are preferred, run this script twice with different -UamiName values.

.PARAMETER SubscriptionId
    Azure subscription ID where the UAMI and Sentinel workspace reside.

.PARAMETER ResourceGroupName
    Resource group in which to create (or find) the UAMI.

.PARAMETER UamiName
    Name of the User-Assigned Managed Identity to create or use.

.PARAMETER WorkspaceResourceId
    Full resource ID of the Microsoft Sentinel (Log Analytics) workspace.
    Format: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.OperationalInsights/workspaces/{name}

.PARAMETER RemediationResourceGroupName
    Resource group on which to assign Monitoring Contributor for PB-AUTO-01 restore operations.
    Defaults to the same resource group as the UAMI if not specified.

.PARAMETER Location
    Azure region for the UAMI if it needs to be created. Defaults to resource group location.

.PARAMETER AssignNotifyRole
    Switch. Assign Microsoft Sentinel Reader (PB-NOTIFY-01). Default: true.

.PARAMETER AssignAutoRole
    Switch. Assign Microsoft Sentinel Responder + Monitoring Contributor (PB-AUTO-01). Default: true.

.PARAMETER WhatIf
    Dry-run mode. Prints all planned actions without executing any Azure mutations.

.EXAMPLE
    .\Bootstrap-AIGovernanceUami.ps1 `
        -SubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
        -ResourceGroupName "rg-example" `
        -UamiName "uami-example" `
        -WorkspaceResourceId "/subscriptions/xxxxxxxx.../workspaces/law-example" `
        -RemediationResourceGroupName "rg-example" `
        -WhatIf

.NOTES
    Author:  x3nc0n / Tank (Automation Engineer)
    Version: 0.1.0-preview.1
    Date:    2026-07-17

    Required Az modules: Az.Accounts, Az.Resources, Az.ManagedServiceIdentity
    Run: Install-Module Az -Scope CurrentUser -Force if modules are missing.

    This script does NOT provision Logic Apps, connectors, or any cost-bearing services.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$UamiName,

    [Parameter(Mandatory = $true)]
    [string]$WorkspaceResourceId,

    [Parameter(Mandatory = $false)]
    [string]$RemediationResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$Location,

    [Parameter(Mandatory = $false)]
    [switch]$AssignNotifyRole = $true,

    [Parameter(Mandatory = $false)]
    [switch]$AssignAutoRole = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Role Definition IDs (built-in, stable) ──────────────────────────────────
$ROLE_SENTINEL_READER    = 'ab8e14d6-4a74-4a29-9ba8-549422addade'  # Microsoft Sentinel Reader
$ROLE_SENTINEL_RESPONDER = '3e150937-b8fe-4cfb-8069-0eaf05ecd056'  # Microsoft Sentinel Responder
$ROLE_MONITORING_CONTRIB = '749f88d5-cbae-40b8-bcfc-e573ddc772fa'  # Monitoring Contributor

function Write-Plan {
    param([string]$Message)
    Write-Host "[PLAN]  $Message" -ForegroundColor Cyan
}

function Write-Action {
    param([string]$Message)
    Write-Host "[ACTION] $Message" -ForegroundColor Green
}

function Write-Skip {
    param([string]$Message)
    Write-Host "[SKIP]  $Message" -ForegroundColor Yellow
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO]  $Message" -ForegroundColor White
}

# ─── Validate login context ───────────────────────────────────────────────────
Write-Info "Validating Azure login context..."
try {
    $context = Get-AzContext -ErrorAction Stop
    if (-not $context -or -not $context.Account) {
        throw "No Azure login context found."
    }
    Write-Info "Logged in as: $($context.Account.Id)"
    Write-Info "Current subscription: $($context.Subscription.Id) ($($context.Subscription.Name))"
} catch {
    Write-Error "Not logged in to Azure. Run Connect-AzAccount first."
    exit 1
}

# ─── Set subscription context without silently switching ─────────────────────
if ($context.Subscription.Id -ne $SubscriptionId) {
    Write-Warning "Current subscription ($($context.Subscription.Id)) differs from target ($SubscriptionId)."
    Write-Warning "This script will NOT silently switch subscriptions. Run Set-AzContext -SubscriptionId '$SubscriptionId' first."
    exit 1
}

# ─── Resolve resource group / location ───────────────────────────────────────
Write-Info "Resolving resource group: $ResourceGroupName"
$rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if (-not $rg) {
    Write-Error "Resource group '$ResourceGroupName' not found in subscription '$SubscriptionId'."
    exit 1
}

if (-not $Location) {
    $Location = $rg.Location
    Write-Info "Using resource group location: $Location"
}

if (-not $RemediationResourceGroupName) {
    $RemediationResourceGroupName = $ResourceGroupName
    Write-Info "RemediationResourceGroupName not specified; defaulting to UAMI resource group: $ResourceGroupName"
}

# ─── Create or retrieve UAMI ──────────────────────────────────────────────────
Write-Info ""
Write-Info "=== UAMI ==="
$uamiResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$UamiName"
Write-Info "Target UAMI resource ID: $uamiResourceId"

$uami = Get-AzUserAssignedIdentity -ResourceGroupName $ResourceGroupName -Name $UamiName -ErrorAction SilentlyContinue

if ($uami) {
    Write-Skip "UAMI '$UamiName' already exists. PrincipalId: $($uami.PrincipalId)"
    $uamiPrincipalId = $uami.PrincipalId
} else {
    Write-Plan "Will create UAMI '$UamiName' in '$ResourceGroupName' ($Location)"
    if ($PSCmdlet.ShouldProcess("$ResourceGroupName/$UamiName", "Create User-Assigned Managed Identity")) {
        $uami = New-AzUserAssignedIdentity -ResourceGroupName $ResourceGroupName -Name $UamiName -Location $Location
        Write-Action "Created UAMI '$UamiName'. PrincipalId: $($uami.PrincipalId)"
        # Allow AAD replication before role assignment
        Write-Info "Waiting 15 seconds for AAD replication before role assignment..."
        Start-Sleep -Seconds 15
        $uamiPrincipalId = $uami.PrincipalId
    } else {
        Write-Plan "(WhatIf) Would create UAMI '$UamiName' — principal ID will be assigned at creation time."
        $uamiPrincipalId = $null
    }
}

# ─── Helper: assign role if not already present ───────────────────────────────
function Ensure-RoleAssignment {
    param(
        [string]$RoleDefinitionId,
        [AllowNull()][AllowEmptyString()][string]$PrincipalId,
        [string]$Scope,
        [string]$RoleDisplayName
    )
    Write-Info "  Checking: $RoleDisplayName on scope ..."
    Write-Info "    Scope: $Scope"

    if ([string]::IsNullOrEmpty($PrincipalId)) {
        Write-Plan "  Would assign '$RoleDisplayName' on $Scope (principal unknown — UAMI not yet created)"
        return
    }

    Write-Info "    Principal: $PrincipalId"

    $existing = Get-AzRoleAssignment `
        -ObjectId $PrincipalId `
        -RoleDefinitionId $RoleDefinitionId `
        -Scope $Scope `
        -ErrorAction SilentlyContinue

    if ($existing) {
        Write-Skip "  Role '$RoleDisplayName' already assigned on $Scope"
        return
    }

    Write-Plan "  Will assign '$RoleDisplayName' on $Scope"
    if ($PSCmdlet.ShouldProcess($Scope, "New-AzRoleAssignment: $RoleDisplayName")) {
        New-AzRoleAssignment `
            -ObjectId $PrincipalId `
            -RoleDefinitionId $RoleDefinitionId `
            -Scope $Scope | Out-Null
        Write-Action "  Assigned '$RoleDisplayName' on $Scope"
    }
}

# ─── PB-NOTIFY-01: Microsoft Sentinel Reader on workspace ────────────────────
if ($AssignNotifyRole) {
    Write-Info ""
    Write-Info "=== PB-NOTIFY-01 Roles ==="
    Ensure-RoleAssignment `
        -RoleDefinitionId $ROLE_SENTINEL_READER `
        -PrincipalId $uamiPrincipalId `
        -Scope $WorkspaceResourceId `
        -RoleDisplayName "Microsoft Sentinel Reader"
}

# ─── PB-AUTO-01: Sentinel Responder + Monitoring Contributor ─────────────────
if ($AssignAutoRole) {
    Write-Info ""
    Write-Info "=== PB-AUTO-01 Roles ==="

    Ensure-RoleAssignment `
        -RoleDefinitionId $ROLE_SENTINEL_RESPONDER `
        -PrincipalId $uamiPrincipalId `
        -Scope $WorkspaceResourceId `
        -RoleDisplayName "Microsoft Sentinel Responder"

    $remediationRgScope = "/subscriptions/$SubscriptionId/resourceGroups/$RemediationResourceGroupName"
    Ensure-RoleAssignment `
        -RoleDefinitionId $ROLE_MONITORING_CONTRIB `
        -PrincipalId $uamiPrincipalId `
        -Scope $remediationRgScope `
        -RoleDisplayName "Monitoring Contributor"
}

# ─── Summary ─────────────────────────────────────────────────────────────────
Write-Info ""
Write-Info "=== Summary ==="
Write-Info "UAMI Resource ID : $uamiResourceId"
Write-Info "Principal ID     : $(if ($uamiPrincipalId) { $uamiPrincipalId } else { '(assigned at creation time)' })"
Write-Info ""
Write-Info "Pass this value as the 'uamiResourceId' parameter to both playbook ARM templates:"
Write-Host "  $uamiResourceId" -ForegroundColor Magenta
Write-Info ""
Write-Info "Role assignments (additive — existing assignments preserved):"
if ($AssignNotifyRole) {
    Write-Info "  Microsoft Sentinel Reader  → $WorkspaceResourceId"
}
if ($AssignAutoRole) {
    Write-Info "  Microsoft Sentinel Responder → $WorkspaceResourceId"
    Write-Info "  Monitoring Contributor       → /subscriptions/$SubscriptionId/resourceGroups/$RemediationResourceGroupName"
}
Write-Info ""
Write-Info "IMPORTANT — post-bootstrap steps:"
Write-Info "  1. Deploy playbook ARM templates with the UAMI resource ID above."
Write-Info "  2. After deployment, authorize the Teams OAuth connection for each playbook."
Write-Info "     Portal: Logic App → API connections → teams-<playbookName> → Edit → Authorize."
Write-Info "  3. Attach playbooks to analytic rules in Sentinel → Analytics → Automated Response."
Write-Info ""

if ($WhatIf) {
    Write-Host "[DRY RUN COMPLETE] No Azure resources were created or modified." -ForegroundColor Yellow
}
