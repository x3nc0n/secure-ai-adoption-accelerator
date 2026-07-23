<#
.SYNOPSIS
    Validates and deploys Microsoft Sentinel - AI Governance Solution artifacts
    to a target Sentinel workspace.

.DESCRIPTION
    Deployment validation script for AIGS. Performs:
      1. Login and subscription context verification (no silent context switch)
      2. Resource group and workspace existence check
      3. ARM template validation (--mode Validate) for each playbook
      4. ARM template deployment (--mode Incremental) for each playbook
      5. Post-deployment resource existence verification
      6. Idempotent redeploy test (second deployment succeeds without conflict)

    Does NOT:
      - Require or wait for alerts to fire
      - Provision cost-bearing services (Logic App consumption plan billed per-execution only)
      - Create connectors (Teams connection must be authorized separately)
      - Switch Az login context without explicit user consent

    Deployment outputs are written to the console. Errors terminate the script.

.PARAMETER TenantId
    Azure AD tenant ID for the target environment.

.PARAMETER SubscriptionId
    Subscription ID for the target resource group.

.PARAMETER ResourceGroupName
    Resource group for deploying Logic App resources.

.PARAMETER WorkspaceName
    Log Analytics / Sentinel workspace name.

.PARAMETER WorkspaceResourceGroupName
    Resource group containing the Sentinel workspace. Defaults to ResourceGroupName.

.PARAMETER Location
    Azure region for deployment. Must match existing resources if deploying alongside them.

.PARAMETER UamiResourceId
    Full resource ID of the UAMI to use. Create with Bootstrap-AIGovernanceUami.ps1.

.PARAMETER TeamsGroupId
    Teams group (team) ID for playbook notification/approval cards.

.PARAMETER TeamsChannelId
    Teams channel ID within the group.

.PARAMETER ApproverGroupObjectId
    AAD object ID of the approver group for PB-AUTO-01.

.PARAMETER DiagnosticsWorkspaceResourceId
    Full resource ID of the Log Analytics workspace for diagnostic settings restoration.
    Defaults to the Sentinel workspace if not specified.

.PARAMETER TemplatesRoot
    Path to the Solutions folder root. Defaults to the parent of the scripts folder.

.PARAMETER SkipValidate
    Skip ARM template validation pass and go directly to deployment.

.PARAMETER SkipDeploy
    Skip deployment; run validation only.

.PARAMETER SkipIdempotentTest
    Skip the second idempotent redeploy test.

.EXAMPLE
    .\Deploy-AIGovernanceValidation.ps1 `
        -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
        -SubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
        -ResourceGroupName "rg-example" `
        -WorkspaceName "law-example" `
        -Location "westus2" `
        -UamiResourceId "/subscriptions/.../userAssignedIdentities/uami-example" `
        -TeamsGroupId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
        -TeamsChannelId "19:xxxx@thread.tacv2" `
        -ApproverGroupObjectId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

.NOTES
    Author:  x3nc0n / Tank (Automation Engineer)
    Version: 0.1.0-preview.1
    Date:    2026-07-17

    Required: Az module (Az.Accounts, Az.Resources), ARM templates under Solutions/
    Validation does NOT require alert firing. KQL correctness is validated separately.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$WorkspaceName,

    [Parameter(Mandatory = $false)]
    [string]$WorkspaceResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$Location,

    [Parameter(Mandatory = $true)]
    [string]$UamiResourceId,

    [Parameter(Mandatory = $true)]
    [string]$TeamsGroupId,

    [Parameter(Mandatory = $true)]
    [string]$TeamsChannelId,

    [Parameter(Mandatory = $true)]
    [string]$ApproverGroupObjectId,

    [Parameter(Mandatory = $false)]
    [string]$DiagnosticsWorkspaceResourceId,

    [Parameter(Mandatory = $false)]
    [string]$TemplatesRoot,

    [Parameter(Mandatory = $false)]
    [switch]$SkipValidate,

    [Parameter(Mandatory = $false)]
    [switch]$SkipDeploy,

    [Parameter(Mandatory = $false)]
    [switch]$SkipIdempotentTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([int]$N, [string]$Message)
    Write-Host ""
    Write-Host "─── Step ${N}: $Message ───" -ForegroundColor Cyan
}

function Write-Ok   { param([string]$M) Write-Host "  ✅ $M" -ForegroundColor Green }
function Write-Fail { param([string]$M) Write-Host "  ❌ $M" -ForegroundColor Red }
function Write-Info { param([string]$M) Write-Host "  ℹ  $M" -ForegroundColor White }

# ─── Resolve defaults ────────────────────────────────────────────────────────
if (-not $WorkspaceResourceGroupName) { $WorkspaceResourceGroupName = $ResourceGroupName }

$workspaceResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$WorkspaceResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName"
if (-not $DiagnosticsWorkspaceResourceId) {
    $DiagnosticsWorkspaceResourceId = $workspaceResourceId
}

if (-not $TemplatesRoot) {
    $TemplatesRoot = Join-Path (Split-Path $PSScriptRoot -Parent) "Solutions\Microsoft Sentinel - AI Governance Solution"
}

$playbookPaths = @{
    'AIGS-Notify-001-TeamsAlert'        = Join-Path $TemplatesRoot "Playbooks\AIGS-Notify-001-TeamsAlert\azuredeploy.json"
    'AIGS-Auto-001-RestoreDiagnostics'  = Join-Path $TemplatesRoot "Playbooks\AIGS-Auto-001-RestoreDiagnostics\azuredeploy.json"
}

$playbookParams = @{
    'AIGS-Notify-001-TeamsAlert' = @{
        playbookName             = 'AIGS-Notify-001-TeamsAlert'
        location                 = $Location
        uamiResourceId           = $UamiResourceId
        teamsGroupId             = $TeamsGroupId
        teamsChannelId           = $TeamsChannelId
    }
    'AIGS-Auto-001-RestoreDiagnostics' = @{
        playbookName                    = 'AIGS-Auto-001-RestoreDiagnostics'
        location                        = $Location
        uamiResourceId                  = $UamiResourceId
        teamsGroupId                    = $TeamsGroupId
        teamsChannelId                  = $TeamsChannelId
        approverGroupObjectId           = $ApproverGroupObjectId
        diagnosticsWorkspaceResourceId  = $DiagnosticsWorkspaceResourceId
    }
}

# ─── Step 1: Verify login context ────────────────────────────────────────────
Write-Step 1 "Verify login context"
$context = Get-AzContext -ErrorAction Stop
if (-not $context -or $context.Tenant.Id -ne $TenantId) {
    Write-Fail "Current context tenant ($($context.Tenant.Id)) does not match target tenant ($TenantId)."
    Write-Info "Run: Connect-AzAccount -TenantId '$TenantId'"
    exit 1
}
if ($context.Subscription.Id -ne $SubscriptionId) {
    Write-Fail "Current context subscription ($($context.Subscription.Id)) does not match target ($SubscriptionId)."
    Write-Info "Run: Set-AzContext -SubscriptionId '$SubscriptionId'"
    exit 1
}
Write-Ok "Login context verified. Tenant: $TenantId, Subscription: $SubscriptionId"

# ─── Step 2: Verify resource group exists ────────────────────────────────────
Write-Step 2 "Verify resource group"
$rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if (-not $rg) {
    Write-Fail "Resource group '$ResourceGroupName' not found."
    exit 1
}
Write-Ok "Resource group '$ResourceGroupName' found ($($rg.Location))."

# ─── Step 3: Verify workspace exists ─────────────────────────────────────────
Write-Step 3 "Verify Sentinel workspace"
$ws = Get-AzResource -ResourceId $workspaceResourceId -ErrorAction SilentlyContinue
if (-not $ws) {
    Write-Fail "Workspace not found: $workspaceResourceId"
    exit 1
}
Write-Ok "Workspace '$WorkspaceName' found."

# ─── Step 4: Verify UAMI exists ──────────────────────────────────────────────
Write-Step 4 "Verify UAMI"
$uami = Get-AzResource -ResourceId $UamiResourceId -ErrorAction SilentlyContinue
if (-not $uami) {
    Write-Fail "UAMI not found: $UamiResourceId"
    Write-Info "Create UAMI with: .\Bootstrap-AIGovernanceUami.ps1"
    exit 1
}
Write-Ok "UAMI found: $($uami.Name)"

# ─── Step 5: Verify template files exist ─────────────────────────────────────
Write-Step 5 "Verify template files"
foreach ($name in $playbookPaths.Keys) {
    if (-not (Test-Path $playbookPaths[$name])) {
        Write-Fail "Template not found: $($playbookPaths[$name])"
        exit 1
    }
    Write-Ok "Template found: $name"
}

# ─── Step 6: ARM template validation ─────────────────────────────────────────
if (-not $SkipValidate) {
    Write-Step 6 "ARM template validation"
    foreach ($name in $playbookPaths.Keys) {
        Write-Info "Validating: $name"
        $result = Test-AzResourceGroupDeployment `
            -ResourceGroupName $ResourceGroupName `
            -TemplateFile $playbookPaths[$name] `
            -TemplateParameterObject $playbookParams[$name] `
            -ErrorAction SilentlyContinue

        if ($result -and $result.Code) {
            Write-Fail "Validation failed for $name : $($result.Message)"
            exit 1
        }
        Write-Ok "Validation passed: $name"
    }
} else {
    Write-Info "Step 6 (ARM validation) skipped via -SkipValidate."
}

# ─── Step 7: Deploy ───────────────────────────────────────────────────────────
if (-not $SkipDeploy) {
    Write-Step 7 "ARM template deployment"
    foreach ($name in $playbookPaths.Keys) {
        Write-Info "Deploying: $name"
        $deployName = "aigs-deploy-$($name.ToLower())-$(Get-Date -Format 'yyyyMMddHHmmss')"
        $deploy = New-AzResourceGroupDeployment `
            -Name $deployName `
            -ResourceGroupName $ResourceGroupName `
            -TemplateFile $playbookPaths[$name] `
            -TemplateParameterObject $playbookParams[$name] `
            -Mode Incremental `
            -ErrorAction Stop

        if ($deploy.ProvisioningState -eq 'Succeeded') {
            Write-Ok "Deployed: $name (deployment: $deployName)"
        } else {
            Write-Fail "Deployment failed for $name. State: $($deploy.ProvisioningState)"
            exit 1
        }
    }
} else {
    Write-Info "Step 7 (deployment) skipped via -SkipDeploy."
}

# ─── Step 8: Post-deployment resource verification ───────────────────────────
if (-not $SkipDeploy) {
    Write-Step 8 "Post-deployment resource verification"
    $playbookNames = @('AIGS-Notify-001-TeamsAlert', 'AIGS-Auto-001-RestoreDiagnostics')
    foreach ($pb in $playbookNames) {
        $resource = Get-AzResource `
            -ResourceGroupName $ResourceGroupName `
            -Name $pb `
            -ResourceType "Microsoft.Logic/workflows" `
            -ErrorAction SilentlyContinue
        if ($resource) {
            Write-Ok "Logic App exists: $pb"
        } else {
            Write-Fail "Logic App not found after deployment: $pb"
            exit 1
        }
    }
    Write-Info "NOTE: Teams connections require manual OAuth authorization before playbooks are functional."
}

# ─── Step 9: Idempotent redeploy test ────────────────────────────────────────
if (-not $SkipDeploy -and -not $SkipIdempotentTest) {
    Write-Step 9 "Idempotent redeploy test"
    foreach ($name in $playbookPaths.Keys) {
        Write-Info "Re-deploying: $name (idempotency check)"
        $deployName2 = "aigs-idem-$($name.ToLower())-$(Get-Date -Format 'yyyyMMddHHmmss')"
        $deploy2 = New-AzResourceGroupDeployment `
            -Name $deployName2 `
            -ResourceGroupName $ResourceGroupName `
            -TemplateFile $playbookPaths[$name] `
            -TemplateParameterObject $playbookParams[$name] `
            -Mode Incremental `
            -ErrorAction Stop

        if ($deploy2.ProvisioningState -eq 'Succeeded') {
            Write-Ok "Idempotent redeploy passed: $name"
        } else {
            Write-Fail "Idempotent redeploy failed for $name. State: $($deploy2.ProvisioningState)"
            exit 1
        }
    }
} else {
    Write-Info "Step 9 (idempotent test) skipped."
}

# ─── Final summary ────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "══════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  AIGS Deployment Validation Complete ✅" -ForegroundColor Green
Write-Host "══════════════════════════════════════════════════" -ForegroundColor Green
Write-Info "Resource Group : $ResourceGroupName"
Write-Info "Workspace      : $WorkspaceName"
Write-Info "UAMI           : $UamiResourceId"
Write-Host ""
Write-Info "Post-deployment manual steps:"
Write-Info "  1. Authorize Teams OAuth connections for both playbooks in Azure Portal."
Write-Info "  2. Attach playbooks to analytic rules: Sentinel → Analytics → [rule] → Automated Response."
Write-Info "  3. Run Remove-AIGovernanceValidation.ps1 to verify clean removal when ready."
