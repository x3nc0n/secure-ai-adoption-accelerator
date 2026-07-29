# Project Context

- **Owner:** x3nc0n
- **Project:** Microsoft Sentinel AI Governance solution
- **Stack:** Azure Logic Apps, Sentinel incidents, Microsoft Graph, Azure APIs, Security Copilot
- **Created:** 2026-07-16T17:01:37.788-07:00

## Learnings

- Playbooks are desired, especially when integrated with Security Copilot.
- **Version label discipline:** Human-facing docs (PREREQUISITES.md line 3, ReleaseNotes.md section headers, CHANGELOG.md heading) must be updated atomically with every package version bump. The official generator writes back `_solutionVersion` to the data manifest but does not touch Markdown docs — these are Tank's packaging responsibility. When the reviewer catches a mismatch, fix only the three doc surfaces; never touch YAML/KQL content. CHANGELOG `[Unreleased]` heading should also have its footer reference link updated to point from the new tag.
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

### 2026-07-23 — Module E Packaging Gate: AIGS-AM001 Promotion & 3.0.6 Release

**Scope:** Promote AM001 from guids.json `_roadmap` to resolved; wire manifest; regenerate package 3.0.6.
**Authorized changes:** `guids.json`, `Data/Solution_AIGovernance.json`, `Package/` (generated).
**Read inputs:** morpheus-module-e-contract-acceptance.md, neo-module-e-content-implementation.md, switch-module-e-validation-gates.md, morpheus-documentation-consistency.md.

#### Changes

| File | Change |
|------|--------|
| `guids.json` | `AIGS-AM001-UnauthorizedModelDeployment` moved from `_roadmap.analyticRules` → top-level `analyticRules`; `status` → `"resolved"` |
| `Data/Solution_AIGovernance.json` | `"Analytic Rules/AIGS-AM001-UnauthorizedModelDeployment.yaml"` appended as 6th rule; `Version` auto-bumped `3.0.5` → `3.0.6` by generator write-back |
| `Package/3.0.6.zip` | NEW — generated release archive (48,992 bytes) |
| `Package/mainTemplate.json` | Regenerated — 18 resources (1 contentPackage, 13 contentTemplates, 4 Watchlists) |
| `Package/createUiDefinition.json` | Regenerated |
| `Package/testParameters.json` | Regenerated |
| `Package/3.0.5.zip` | REMOVED (obsolete) |
| `Workbooks/WorkbooksMetadata.json` | No change (consistent with Module B/C precedent) |

#### Generator mechanics
Command: `createSolutionV3.ps1 -VersionMode local -VersionBump patch`
Junction: `Tools` → `..\Azure-Sentinel\Tools` created pre-run, removed post-run (no repo files created).
Generator auto-incremented 3.0.5 → 3.0.6 and wrote back to Solution_AIGovernance.json.

#### Validation results

| Validator | Result | Detail |
|-----------|--------|--------|
| Test-AIGovernanceSource.ps1 | ✅ PASS | 15 checks, 119 passed, 0 warnings, 0 failures |
| Test-ModuleEChecks.ps1 | ✅ PASS | 16 assertions, 16 passed |
| Test-ModuleCChecks.ps1 | ✅ PASS | 10 assertions, 10 passed |

Check 13 (roadmap gate): `PASS  14 roadmap path(s) checked — none deployed prematurely`
Package shape (Check 12): `valid ARM template with 18 resource(s)` — 1 pkg + 13 templates + 4 Watchlists.
AM001 contentId: `_analyticRulecontentId6 = 752bbac1-66ff-4bba-93f7-46a57bbd793d`
`_solutionVersion = 3.0.6`; docs = `3.0.6-preview.1` (consistent per convention).

#### Key learnings

- V3 generator resolves `commonFunctions.ps1` via `$repositoryBasePath + "Tools/..."` relative to the `Solutions/` parent dir. When the solution repo differs from Azure-Sentinel, use a Windows directory junction to satisfy the lookup without copying files into source control. Remove junction immediately after generation.
- Generator auto-increments version AND writes back to `Data/Solution_AIGovernance.json`. Leave the manifest at the pre-bump version before calling with `-VersionBump patch`; do not pre-set the target version manually or the output version will be N+1.
- Check 13 (roadmap path gate) is the authoritative signal that a `_roadmap` entry has been deployed and must be promoted. No file at a roadmap path ⇒ gate passes cleanly.

### 2026-07-24 — Module E 3.0.6 Regeneration (Hunt Correction)

**Trigger:** Morpheus reviewer-authorized hunt correction: `ActivityStatusValue in~ ("Success","Succeeded")`
(was single-value). No other source changes; same-version regeneration required.

**Convention:** Manifest reset `3.0.6` → `3.0.5` before generator invocation so patch-bump produces `3.0.6` (not `3.0.7`). Junction created/removed as before.

**Result:** 3.0.6.zip replaced (49,057 bytes); mainTemplate/createUiDefinition/testParameters regenerated. Package shape unchanged: 18 resources, 13 templates, 4 Watchlists. `_solutionVersion = 3.0.6`. Hunt correction confirmed embedded (4 occurrences of escaped `in~("Success","Succeeded")` in mainTemplate.json).

**Validators:** Test-AIGovernanceSource.ps1 15/15 PASS (119 passed, 0 warnings, 0 failures); Test-ModuleEChecks.ps1 16/16 PASS; Test-ModuleCChecks.ps1 10/10 PASS.

**Key learning:** Same-version regeneration pattern = reset manifest to N-1, run `-VersionBump patch`, generator writes back N. Consistent with B/C precedent.
