# Project Context

- **Owner:** x3nc0n
- **Project:** Microsoft Sentinel AI Governance solution
- **Stack:** Azure Logic Apps, Sentinel incidents, Microsoft Graph, Azure APIs, Security Copilot
- **Created:** 2026-07-16T17:01:37.788-07:00

## Learnings

- Playbooks are desired, especially when integrated with Security Copilot.
- Automation must account for cross-platform identity, permissions, approvals, and rollback.
- Security Copilot Logic Apps connector is **GA** (since April 1, 2024) but does **NOT** support Managed Identity — requires OAuth user account or client certificate. This is a hard architectural constraint for all enrichment playbooks.
- Power Platform API (Copilot Studio agent disable) has no native Logic Apps connector. Requires HTTP action + Power Platform Environment Admin role on the MI, which is outside Azure RBAC (must be set in PPAC). This is a non-standard permission setup blocker.
- `Add task to incident` and `Entities – Get Accounts/IPs/Hosts` Sentinel connector actions are **Preview** — do not use in production playbooks.
- Best first-party Security Copilot + Sentinel playbook examples live in `Azure/Security-Copilot` → `Logic Apps/SecurityCopilot-Sentinel-Incident-Investigation/` (true integration — submits prompts with dynamic entity values, writes back to Sentinel incident).
- MVP recommendation: PB-AUTO-01 (AutoRemediate-DiagnosticLoggingRestored) — zero destructive risk, all GA connectors, directly supports Trinity Tier A control C6.
- Security Copilot follow-up: PB-ENRICH-01 — true enrichment integration, adaptable from existing Azure/Security-Copilot example. Blocked only by SCU licensing decision.
- 9 design decisions must be resolved before implementation: SCU allocation, Copilot connector auth account, MI model, watchlist schema, approval channel, approval timeout behavior, Power Platform MI permissions, automation rule scope, and notification channel.

## Work Log

### 2026-07-16 — Playbook Implementation Feasibility Assessment
- Read all three inbox artifacts: morpheus, trinity, neo proposals.
- Searched `Azure/Azure-Sentinel` and `Azure/Security-Copilot` GitHub repos for Security Copilot playbook examples.
- Verified GA vs Preview status of all relevant connectors via Microsoft Learn and web research.
- Produced 8-playbook catalog with full per-playbook specs.
- Wrote proposal to `.squad/decisions/inbox/tank-playbook-feasibility.md`.

### 2026-07-16 — Verified Corrections (Switch Playbook Review)

**Critical authentication/API corrections:**
- ❌ Alert trigger = GA → ✅ **Preview** (cannot attach to automation rules)
- ❌ Entity trigger = GA → ✅ **Preview** (manual trigger only)
- ❌ Client Certificate Auth for Security Copilot → ✅ **Removed** (NOT supported; OAuth delegated only)
- ❌ Graph endpoint: `POST /servicePrincipals/{id}/disableServicePrincipal` → ✅ **DOES NOT EXIST** (use `PATCH /servicePrincipals/{id}` + `{ "accountEnabled": false }`)
- ❌ Copilot Studio API: generic PATCH `status: disabled` → ✅ **Use dedicated quarantine endpoint** (`POST /copilotstudio/environments/{envId}/bots/{botId}/api/botQuarantine/SetAsQuarantined`)
- ❌ Diagnostic settings risk: "zero destructive" → ✅ **"Low destructive"** (can overwrite existing configs; 5-settings-per-resource limit)

**MVP verdict maintained:** ✅ PB-AUTO-01 is sound with corrected risk label.

**Evidence source:** Microsoft Learn (2026-07-16), GitHub LogicAppsUX issue validation, Microsoft Graph API documentation

### 2026-07-17 — AI Governance Solution Packaging Repair (Official Generator Run)

**Scope:** Repair source layout and prove official `createSolutionV3.ps1 -VersionMode local` generation.  
**Authorized changes:** Watchlist structure, Data manifest, SolutionMetadata, guids.json, sync script.  
**Authorized output:** `Package/` (generated; do not hand-edit).

#### Source layout changes

| Path | Change |
|------|--------|
| `Data/Watchlists/` (deleted) | 4 legacy files removed — wrong location, wrong schema |
| `Watchlists/AIGS_ContentFilterPolicies/AIGS_ContentFilterPolicies.json` | NEW — full ARM template; `itemsSearchKey=ItemKey`, `rawContent` = LF-normalized CSV |
| `Watchlists/AIGS_ContentFilterPolicies/AIGS_ContentFilterPolicies.csv` | NEW — `ItemKey` first col, `Status` col, 1 Template row, no PLACEHOLDER/nil tokens |
| `Watchlists/AIGS_ApprovedModels/AIGS_ApprovedModels.json` | NEW — same pattern |
| `Watchlists/AIGS_ApprovedModels/AIGS_ApprovedModels.csv` | NEW — same pattern |
| `Data/Solution_AIGovernance.json` | Version→3.0.0 (numeric), TemplateSpec→false, Logo→valid GitHub raw URL, support.link→https://github.com/x3nc0n, Watchlists paths updated to per-folder structure, Workbooks entry added, hunt filename corrected to `AIGS-Hunt-AIModelDeploymentChanges.yaml`, _expansionNote removed, Metadata property **moved last** (critical: fixes op_Addition generator crash) |
| `SolutionMetadata.json` | Reduced to metadata-only: publisherId, offerId, firstPublishDate, providers, categories, support |
| `guids.json` | Watchlist paths updated, searchKey→ItemKey, workbook file corrected, hunt key/file corrected, unresolved items moved to `_roadmap` section |
| `scripts/Sync-AIGovernanceWatchlists.ps1` | NEW — validates ItemKey-first schema, normalizes LF, updates rawContent in ARM template JSONs |

#### Generator run

**Command:**
```powershell
& "...\Azure-Sentinel\Tools\Create-Azure-Sentinel-Solution\V3\createSolutionV3.ps1" `
  -SolutionDataFolderPath "...\Azure-Sentinel\Solutions\Microsoft Sentinel - AI Governance Solution\Data" `
  -VersionMode local
```

**Result:** ✅ SUCCESS — Package created at `Solutions/Microsoft Sentinel - AI Governance Solution/Package/`  
**Artifacts:** `mainTemplate.json` (158 KB, 10 resources), `createUiDefinition.json` (19 KB, 5 steps: workbooks/analytics/huntingqueries/watchlists/playbooks), `3.0.1.zip`, `testParameters.json`  
**Warning (non-fatal):** arm-ttk not installed — TTK validation skipped; generator core completed.

#### Root-cause notes

1. **op_Addition crash** — Generator `PrepareSolutionMetadata` applies `| Where-Object {}` filter on resources. When exactly 1 resource is present, PowerShell returns a PSObject (not array). Subsequent `+=` on the PSObject fails. Fix: put `Metadata` property **last** in the Data file so all other content resources are accumulated first; filter then returns multi-item array.
2. **WorkbooksMetadata.json** — Generator's `GetWorkbookDataMetadata` downloads `{repositoryBasePath}Workbooks/WorkbooksMetadata.json`. Missing file triggers `break` propagating to outer foreach (PowerShell `break` in function propagates to caller's loop). Fix: created minimal stub at `{checkout}/Workbooks/WorkbooksMetadata.json` with `templateRelativePath: "AIGovernanceSolution.json"`.
3. **Generator writes Package to CWD** — Generator uses absolute paths for WebClient.DownloadString but relative `Solutions/{name}/Package` path for file output. Output resolves to the working directory (source repo), not the checkout. This is expected behavior when not running from Azure-Sentinel root.

### 2026-07-17 — Formal Playbook README Review & Revision (Independent Revision Owner)

**Scope:** Revise two playbook readmes rejected for factual and architectural inaccuracies. Original author (Switch) locked out; Tank assumes independent revision owner role.

**Formal Review Findings (all corrected):**

#### PB-NOTIFY-001-TeamsAlert (Notification)

**False/Invented Claims Removed:**
- ❌ "Automation rules are deployed in the same template" → ✅ REMOVED + documented: "This is a **manual process** — the deployment template does **not** include automation rules. Each deployment must configure automation rules separately."
- ❌ Parameters: `workspaceResourceId`, `notificationTeamsWebhookUrl`, `emailFallbackRecipients` (do not exist in azuredeploy.json) → ✅ REMOVED
- ❌ "Webhook fallback posts plain text without adaptive card formatting" (misleading; webhook fallback not implemented) → ✅ REMOVED
- ❌ "Retry up to 3 times with exponential backoff" (NOT implemented in template) → ✅ REMOVED
- ❌ "Email fallback" and "Circuit breaker" (NOT implemented) → ✅ REMOVED

**Accurate Corrections Added:**
- ✅ Actual parameters documented: `playbookName`, `location`, `uamiResourceId`, `teamsGroupId`, `teamsChannelId` (verified against azuredeploy.json)
- ✅ Deployed state: `Enabled` (verified from template line 294: `"state": "Enabled"`)
- ✅ Teams connector requires OAuth delegated post-deployment authorization (verified from template metadata and connection setup)
- ✅ UAMI role: `Microsoft Sentinel Reader` only, read-only scope (verified from template identity and role-name pattern)
- ✅ Failure behavior: accurate, fail-closed (no retries, logged to incident comment and AzureDiagnostics)
- ✅ Clarified: "Add comment to incident" step executed on success (verified from template workflow definition)

#### PB-AUTO-001-RestoreDiagnostics (Approval-Gated Remediation)

**False/Invented Claims Removed:**
- ❌ Parameters: `workspaceResourceId`, `targetResourceGroupId`, `notificationTeamsChannelId`, `emailFallbackRecipients` (do not exist in azuredeploy.json) → ✅ REMOVED
- ❌ "Precondition: prior approved diagnostic setting from AIGS_ContentFilterPolicies watchlist or ARM tags" (watchlist fallback NOT implemented; only GET check performed) → ✅ REMOVED
- ❌ "Retry up to 3 times with exponential backoff" (NOT implemented) → ✅ REMOVED
- ❌ "Circuit breaker" and "escalate to emailFallbackRecipients" (NOT implemented) → ✅ REMOVED
- ❌ "Incident status updated to Active on rejection" (NOT explicitly implemented in template) → ✅ REMOVED
- ❌ "Restore arbitrary prior state" (playbook writes only dedicated setting, not prior state) → ✅ REMOVED + clarified: "does not restore prior state; only ensures dedicated named setting"
- ❌ "Watchlist lookup" procedure documented as active (watchlist NOT queried in template) → ✅ REMOVED

**Accurate Corrections Added:**
- ✅ Deployed state: `Disabled` (verified from template line 294: `"state": "Disabled"`)
- ✅ Actual parameters documented: `playbookName`, `location`, `uamiResourceId`, `teamsGroupId`, `teamsChannelId`, `approverGroupObjectId`, `approvalTimeoutMinutes`, `diagnosticsWorkspaceResourceId` (verified against azuredeploy.json parameters section)
- ✅ CD005 rule GUID gate: `7c4e1a9d-3b6f-4e2a-b8c5-0d7f1e3a6b82` (verified from template logic line 392)
- ✅ CognitiveServices resource type gate: `microsoft.cognitiveservices/accounts` (verified from template line 410)
- ✅ Actual state machine documented:
  - Gate 1: CD005 rule GUID check → exit if fail
  - Gate 2: CognitiveServices resource type check → exit if fail
  - Approval: Teams webhook (bi-directional, OAuth required)
  - Compliance check: GET diagnostic setting, verify workspace ID + allLogs + AllMetrics
  - No-op path: if already compliant, skip PUT
  - Remediation path: PUT AIGS-Required-Diagnostics setting only (verified from template PUT payload lines 479–495)
- ✅ Failure behavior: accurate, fail-closed (no auto-approve on timeout, no retry, all outcomes logged to incident comment)
- ✅ Clarified: "Diagnostic setting PUT is atomic; no partial state left on failure"
- ✅ UAMI roles: `Monitoring Contributor` (on target resource scope) + `Sentinel Responder` (on workspace)
- ✅ "Does NOT do" section: Explicitly documents playbook **cannot** modify content filters, model deployments, RAI policies, RBAC, or other resource types
- ✅ Post-deployment wiring documented: "Manual process — the deployment template does **not** include automation rules. Each deployment must configure the automation rule separately."

**Evidence Cross-Checked:**
- All parameters verified against azuredeploy.json (both playbooks)
- All workflow actions verified against Logic App definition in template
- All gates and conditions verified line-by-line in template definition
- Deployed state (`state` property) verified for both playbooks
- Identity and RBAC verified from template identity block and connection setup

**Version Consistency:**
- ✅ Both readmes use version text: `1.0.0-preview.1` (consistent with template hidden tags and document scope)

**Markdown Validation:**
- ✅ All internal links/references validated (no broken links to non-existent sections)
- ✅ All parameter table links match actual parameters in deployment section
- ✅ All gate/condition descriptions match template logic

**Files Modified:**
- `Solutions/Microsoft Sentinel - AI Governance Solution/Playbooks/AIGS-Auto-001-RestoreDiagnostics/readme.md` (revised)
- `Solutions/Microsoft Sentinel - AI Governance Solution/Playbooks/AIGS-Notify-001-TeamsAlert/readme.md` (revised)
- `.squad/agents/tank/history.md` (this file, work log updated)
