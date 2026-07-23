# AIGS-Auto-001-RestoreDiagnostics

**Playbook ID:** PB-AUTO-01
**Type:** Approval-Gated Auto-Remediation
**Solution:** Microsoft Sentinel — AI Governance Solution
**Version:** 0.1.0-preview.4
**Author:** x3nc0n

---

## Overview

AIGS-Auto-001-RestoreDiagnostics remediates configuration drift by ensuring a single dedicated diagnostic setting (`AIGS-Required-Diagnostics`) is present on eligible Azure AI resources (Azure CognitiveServices accounts) with the required log/metric configuration. The playbook:

1. Validates the incident is from CD005 (Configuration Drift analytic rule)
2. Extracts the affected CognitiveServices resource ID from the incident
3. Requests explicit human approval via Teams adaptive card
4. (If approved) Reads the current diagnostic setting via ARM API
5. (If not compliant) Writes **only** the dedicated setting; does not modify other settings
6. (If already compliant) Skips the write and documents as "no-op"

**Risk level:** Low (diagnostic settings only — adds logging; does not modify model config, content filters, access policies, or resource state)
**Failure mode:** Fail-closed (no approval = no change; no Teams delivery = no change)

---

## Trigger

| Attribute | Value |
|-----------|-------|
| **Trigger type** | Microsoft Sentinel — When Azure Sentinel incident creation rule is triggered |
| **Trigger scope** | CD005 Configuration Drift rule incidents only (hardcoded rule GUID: `7c4e1a9d-3b6f-4e2a-b8c5-0d7f1e3a6b82`) |
| **Attachment** | Sentinel incident details + relatedEntities (must include AzureResource of type Microsoft.CognitiveServices/accounts) |

If the incident does not originate from CD005, the playbook logs a gate failure comment and exits. If the incident has no CognitiveServices entity, the playbook logs a resource type gate failure and exits.

---

## Approval Gate

Approval is **mandatory** and fail-closed:

| Component | Method | Purpose |
|-----------|--------|---------|
| Approval request | Teams connector: "Post adaptive card and wait for a response" (webhook-based) | Bi-directional — Approve/Reject buttons require OAuth connection |
| Approval destination | Teams channel (specified by `teamsGroupId` + `teamsChannelId`) | Approver group members receive and respond to the card |
| Approval timeout | Configurable: default 240 minutes (4 hours); minimum 30 min, maximum 1440 min | **No auto-approve on timeout.** Expired window → incident remains Active for manual review |
| Response options | Approve, Reject, Timeout | Only "Approve" proceeds to remediation |

**Fail-closed timeout:** If the approval window expires with no response, the playbook logs a timeout comment to the incident and stops. No automatic remediation occurs.

---

## State Machine

### Preconditions (All Required)

| # | Check | Gate Type | If Failed |
|---|-------|-----------|-----------|
| 1 | relatedAnalyticRuleIds contains CD005 GUID `7c4e1a9d-3b6f-4e2a-b8c5-0d7f1e3a6b82` | Rule GUID gate | Log: "🚫 **PB-AUTO-01 RULE GATE FAILED**: relatedAnalyticRuleIds does not contain the required CD005 rule GUID…" → Exit |
| 2 | relatedEntities includes an AzureResource with `kind=AzureResource` and resourceId containing `microsoft.cognitiveservices/accounts` | Resource type gate | Log: "🚫 **PB-AUTO-01 RESOURCE TYPE GATE FAILED**: No AzureResource entity of type Microsoft.CognitiveServices/accounts found…" → Exit |

If either gate fails, the playbook writes a logged reason to the incident comment and exits without requesting approval.

---

### Approval Decision Path

**If approved:**

1. **GET diagnostic setting** — ARM API: `GET /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.CognitiveServices/accounts/{account}/providers/microsoft.insights/diagnosticSettings/AIGS-Required-Diagnostics`

2. **GET diagnostic setting outcome — three exclusive branches:**

   **Branch A — GET Succeeded (HTTP 200):**
   The workflow runs two Filter array actions on the returned `properties.logs` and `properties.metrics` arrays:
   - **Filter_Logs_Enabled**: retains only entries where `categoryGroup == allLogs` AND `enabled == true`
   - **Filter_Metrics_Enabled**: retains only entries where `category == AllMetrics` AND `enabled == true`

   **Compliance check (all three required):**
   - `workspaceId` (case-insensitive) matches `diagnosticsWorkspaceResourceId` parameter
   - Filter_Logs_Enabled result is non-empty (at least one enabled allLogs entry)
   - Filter_Metrics_Enabled result is non-empty (at least one enabled AllMetrics entry)

   - **If all three pass → Already compliant** → Log: "✅ **PB-AUTO-01 ALREADY COMPLIANT**: Diagnostic setting AIGS-Required-Diagnostics on [resource] verified at [timestamp] — workspaceId matches, allLogs enabled=true entry confirmed, AllMetrics enabled=true entry confirmed. No PUT performed." → Exit (no-op).
   - **If any fails → Not compliant** → Proceed to PUT (remediation).

   **Branch B — GET Failed with HTTP 404 (setting not found):**
   The dedicated setting `AIGS-Required-Diagnostics` does not exist on the resource. PUT is permitted after approval — the setting will be created.

   **Branch C — GET Failed with HTTP 403, 429, 5xx, timeout, or other error:**
   **Fail closed.** No PUT is performed. Log: "🔴 **PB-AUTO-01 GET FAILED — FAIL CLOSED**: GET of AIGS-Required-Diagnostics on [resource] returned status [code] at [timestamp]. This is not a 404 (setting not found) — possible 403 (access denied), 429 (throttled), or 5xx (service error). No PUT performed. Run ID: [id]. Manual investigation required." Incident remains Active for manual SOC triage.

3. **PUT diagnostic setting (remediation) — reachable only from Branch A (non-compliant) or Branch B (404):**
   ```
   PUT /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.CognitiveServices/accounts/{account}/providers/microsoft.insights/diagnosticSettings/AIGS-Required-Diagnostics

   {
     "properties": {
       "workspaceId": "{diagnosticsWorkspaceResourceId}",
       "logs": [
         {
           "categoryGroup": "allLogs",
           "enabled": true
         }
       ],
       "metrics": [
         {
           "category": "AllMetrics",
           "enabled": true
         }
       ]
     }
   }
   ```

   - **Success:** Log: "✅ **PB-AUTO-01 RESTORED**: Diagnostic setting AIGS-Required-Diagnostics ensured on [resource] at [timestamp]. categoryGroup allLogs and category AllMetrics enabled to workspace [workspace]. No other diagnostic settings were modified."
   - **Failure (ARM error):** Log: "🔴 **PB-AUTO-01 ARM FAILURE**: PUT of AIGS-Required-Diagnostics on [resource] failed at [timestamp]. Run ID: [logic app run name]. Verify UAMI Monitoring Contributor on resource scope. Manual remediation required."

**If rejected:**
Log: "❌ **PB-AUTO-01 REJECTED**: Approver declined restoration at [timestamp]. No changes made to [resource]. Incident remains Active for manual SOC triage."

**If timeout (no response within timeout window):**
Log: "⏱️ **PB-AUTO-01 TIMED OUT**: Approval window (PT{minutes}M) expired at [timestamp]. No changes made to [resource]. Incident remains Active. Manual SOC triage required."

**If approval card delivery fails (Teams error):**
Log: "🔴 **PB-AUTO-01 TEAMS DELIVERY FAILED**: Approval card could not be delivered at [timestamp]. Verify Teams connection is authorized (delegated OAuth) and teamsGroupId/teamsChannelId are correct. No changes made. Manual remediation required."

---

## Identity and Permissions

| Attribute | Value |
|-----------|-------|
| **Identity type** | User-Assigned Managed Identity (UAMI) |
| **UAMI roles** | `Monitoring Contributor` (on target resource scope) + `Microsoft Sentinel Responder` (on Sentinel workspace) |
| **Monitoring Contributor scope** | Resource group containing the CognitiveServices accounts only (not subscription-wide) |
| **Sentinel Responder scope** | Sentinel workspace resource ID |
| **Teams connection** | OAuth — delegated connection (separate from UAMI; requires service account authorization post-deployment) |

`Monitoring Contributor` grants permission to read and write `Microsoft.Insights/diagnosticSettings` on resources in the target resource group. It does **not** grant permission to modify model deployments, content filters, RAI policies, access control, or any other resource type.

---

## Deployment State

| Attribute | Value |
|-----------|-------|
| **Deployed state** | `Disabled` |
| **Prerequisites met before enabling** | (1) Teams OAuth connection must be authorized; (2) UAMI must have Monitoring Contributor role on target resource scope and Sentinel Responder role on workspace; (3) Approver group must exist in Entra ID |

The Logic App deploys in `Disabled` state. Before enabling, verify:
1. UAMI role assignments are in place (use `Get-AzRoleAssignment -ObjectId {uamiId}` to verify)
2. Teams OAuth connection is authorized in Azure Portal (navigate to Logic App → **API connections** → **teams-AIGS-Auto-001-RestoreDiagnostics** → **Edit API connection** → **Authorize**)
3. Approver group object ID is correct (matches Entra group whose members will receive approval requests)

To enable: In Azure Portal, open the Logic App workflow → **Edit** → **Enabled** → **Save**.

---

## Parameters

Deployment accepts the following parameters (provided at template deployment time):

| Parameter | Type | Required | Notes |
|-----------|------|----------|-------|
| `playbookName` | string | No | Name of the Logic App resource; default: `AIGS-Auto-001-RestoreDiagnostics` |
| `location` | string | No | Azure region; default: resource group location |
| `uamiResourceId` | string | ✅ Yes | Resource ID of the User-Assigned Managed Identity. Format: `/subscriptions/{subscriptionId}/resourceGroups/{resourceGroup}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/{identityName}` |
| `teamsGroupId` | string | ✅ Yes | Microsoft Teams group (team) object ID for the approval destination |
| `teamsChannelId` | string | ✅ Yes | Microsoft Teams channel ID within the group for the approval card |
| `approverGroupObjectId` | string | ✅ Yes | Entra group object ID whose members receive approval requests |
| `approvalTimeoutMinutes` | int | No | Approval window duration (minutes); default: 240 (4 hours); minimum: 30; maximum: 1440 |
| `diagnosticsWorkspaceResourceId` | string | ✅ Yes | Resource ID of the Log Analytics workspace for the diagnostic setting destination. Format: `/subscriptions/{subscriptionId}/resourceGroups/{resourceGroup}/providers/Microsoft.OperationalInsights/workspaces/{name}` |

---

## Post-Deployment Manual Wiring

The playbook does **not** automatically attach to analytic rules. Manual wiring is required:

1. **Identify the CD005 Configuration Drift analytic rule** in Microsoft Sentinel (rule ID: CD005 or search by title)

2. **Create an automation rule** that triggers this playbook on CD005 incidents:
   - Automation rule name: e.g., `AIGS-Auto-Remediate-CD005`
   - Trigger condition: `Incident status is Created`
   - Triggered rules: Select CD005 rule
   - Run playbook action: Select `AIGS-Auto-001-RestoreDiagnostics`
   - Playbook parameters: Auto-filled from template parameters

This is a **manual process** — the deployment template does **not** include automation rules. Each deployment must configure the automation rule separately.

---

## Failure Behavior

| Failure Condition | Behavior |
|------------------|---------|
| ARM GET returns 403 (access denied) | **Fail closed**: Log "GET FAILED — FAIL CLOSED" with status 403 to incident comment; no PUT performed. Verify UAMI Monitoring Contributor on resource scope. |
| ARM GET returns 429 (throttled) | **Fail closed**: Log "GET FAILED — FAIL CLOSED" with status 429 to incident comment; no PUT performed. Wait and manually re-trigger. |
| ARM GET returns 5xx or timeout | **Fail closed**: Log "GET FAILED — FAIL CLOSED" with status code to incident comment; no PUT performed. Manual investigation required. |
| ARM GET returns 404 (setting absent) | PUT is allowed after approval. If PUT succeeds: log "PB-AUTO-01 CREATED". If PUT fails: log "ARM FAILURE". |
| ARM GET returns 200 but `enabled: false` on allLogs/AllMetrics | Not compliant (filter returns empty array); PUT is performed after approval. |
| PUT fails (ARM error) | Log "🔴 **PB-AUTO-01 ARM FAILURE**" with run ID to incident comment; set incident to Active. Manual remediation required. |
| Teams approval card delivery fails | Log: "Teams delivery failed — verify connection and group/channel IDs"; do not auto-approve; set incident to Active. Manual remediation required. |
| UAMI authentication fails (no role assignment) | Logic App enters failed run state; log to incident comment and `AzureDiagnostics`; no silent failure. |
| Unexpected approval response (malformed card data) | Log: "Unexpected response"; no changes made; incident remains Active for manual review. |
| Teams connection not authorized post-deployment | Playbook attempts to deliver approval card; Teams action fails; log error to incident comment and `AzureDiagnostics`. |

**Fail-closed design:** No condition auto-approves, auto-applies, or retries without explicit approval. All failures produce durable incident comments (retained per workspace retention policy).

---

## Audit Trail

Every execution writes structured comments to the Sentinel incident:

- **Timestamp** (UTC)
- **Playbook run ID** (Logic App run name for cross-reference with `AzureDiagnostics`)
- **Gate checks** (CD005 rule gate pass/fail, resource type gate pass/fail)
- **Approval request details** (sent to team/channel, sent at timestamp, expiration time)
- **Approval response** (approved/rejected/timed out, response timestamp)
- **Remediation action** (PUT performed/skipped, setting name, workspace ID, status)
- **Any errors** (ARM failures, Teams failures, UAMI auth failures)

Incident comments are the **durable response audit trail** and are retained per Sentinel workspace data retention policy.

---

## Rollback

**Diagnostic setting override:**

If the PUT operation writes an incorrect or undesired configuration:

1. Retrieve the current state: `az monitor diagnostic-settings show --resource-id {resourceId} --name AIGS-Required-Diagnostics`
2. Manually correct via ARM CLI: `az monitor diagnostic-settings create --resource-id {resourceId} --name AIGS-Required-Diagnostics --workspace {workspaceId} ...`
3. Or manually correct in Azure Portal: Navigate to the resource → **Monitoring** → **Diagnostic settings** → Edit **AIGS-Required-Diagnostics**

**ARM eventual consistency:**

The diagnostic setting may take 5–30 seconds to propagate. If verification fails immediately after remediation:
1. Wait 5 minutes
2. Re-run: `az monitor diagnostic-settings show --resource-id {resourceId} --name AIGS-Required-Diagnostics`
3. If still not applied, escalate to manual remediation and verify resource access permissions.

**UAMI role recovery:**

If the UAMI loses the `Monitoring Contributor` role mid-execution:
1. The PUT will fail with HTTP 403 (Forbidden)
2. Error is logged to incident comment
3. Re-assign the role: `New-AzRoleAssignment -ObjectId {uamiId} -RoleDefinitionName "Monitoring Contributor" -Scope {resourceGroupId}`
4. Manually remediate or re-trigger the playbook

---

## Deployment Notes

- This playbook deploys as a Logic App (Consumption plan). Cost is per-execution only; no always-on cost.
- The playbook is **disabled** by default and must be manually enabled after post-deployment validation.
- Logic App diagnostic settings are enabled by default, sending run history to the Sentinel workspace (`AzureDiagnostics`).
- The Teams OAuth connection deploys as a separate resource and must be authorized post-deployment before approval cards can be delivered.
- The playbook does **not** share the `Monitoring Contributor` role with AIGS-Notify-001-TeamsAlert. The notification playbook needs only `Microsoft Sentinel Reader`. Roles must not be broadened for consolidation.

---

## What This Playbook Does NOT Do

This playbook is explicitly **not authorized** to and **will not**:
- Modify content filter policies (`Microsoft.CognitiveServices/accounts/raiPolicies/*`)
- Modify model deployments (`Microsoft.CognitiveServices/accounts/deployments/*`)
- Modify or delete other diagnostic settings (only the dedicated `AIGS-Required-Diagnostics` setting is touched)
- Modify RBAC role assignments
- Delete any Azure resource
- Modify Sentinel analytic rules or automation rules
- Restore prior or arbitrary diagnostic setting configurations; only writes the dedicated named setting per approval

---

## Related Playbooks

| Playbook | Relationship |
|----------|-------------|
| AIGS-Notify-001-TeamsAlert | Notification-only; fires first on incident creation for all modules; no approval |
