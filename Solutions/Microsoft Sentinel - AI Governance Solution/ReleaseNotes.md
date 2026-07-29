# Release Notes — Microsoft Sentinel – AI Governance Solution

---

## v3.0.6-preview.1 — Azure General Module E Batch

**Release date:** 2026-07-23
**Release type:** Preview
**Scope:** Module E Azure General vertical slice — CognitiveServices unauthorized deployment detection with fail-closed baseline matching

- Added `AIGS-AM001-UnauthorizedModelDeployment`: fail-closed baseline-matched detection of successful `Microsoft.CognitiveServices/accounts/deployments/write` operations not present in the `AIGS_ApprovedModels` baseline. Runs every 1 hour, 4-hour lookback, composite join key `AccountName/DeploymentName`, deterministic match against `Status=Active` baseline. Empty/template-only baseline yields zero findings.
- Added `AIGS-Hunt-AIModelDeploymentChanges`: inventory of all successful deployment operations and extracted account/deployment name values. Use as discovery basis for populating `AIGS_ApprovedModels` before enabling unauthorized-deployment detection.
- Reused `AIGS_ApprovedModels` watchlist (schema: `ItemKey,AccountName,DeploymentName,ApprovedVersion,Status,BaselineOwner,LastUpdated`; `itemsSearchKey=ItemKey`; shared with Module A; detection join key is composite `AccountName/DeploymentName`; template row only shipped).
- Added workbook Module E tiles: deployment activity inventory and unauthorized finding discovery surface (isfuzzy-guarded, missing-table safe).
- Rewrote PREREQUISITES Module E: documents fail-closed baseline semantics, composite join key, operator exact operation/status values, resource identity from ARM path, analyst manual verification requirement via Azure Resource Manager, and explicit scope boundaries (no region/model-version/SKU enforcement; no auto-remediation; no deletion detection; deployment-name-only matching; no request-body Properties parsing).
- Stale "pending Trinity evidence contract" language removed. Stale "approved regions" and "model version enforcement" claims removed from documentation.
- Connector verified GA: `Azure Activity Logs` built-in, no additional connector required.
- Switch validator gate Module E: 16/16 checks passed (operation case, status values, fail-closed semantics, composite key, baseline guards, artifact presence, GUID registry consistency, watchlist structure, rule metadata completeness).

**Design basis:** Morpheus Module E Design Gate (`morpheus-module-e-design-gate.md`). Fail-closed semantics adopted from Module C CD003 pattern (CD003 article). Multi-provider scope (Azure ML, other Azure AI providers) remains roadmap-only pending Trinity verification and operation-name discovery for those providers.

---

## v3.0.5-preview.1 — M365 Copilot Module C Batch

**Release date:** 2026-07-23
**Release type:** Preview
**Scope:** Module C Microsoft 365 Copilot vertical slice — observed-state model binding drift

- Added `AIGS-CD003-CopilotAgentModelDrift`: fail-closed inner-join detection of M365 Copilot agent model drift. Runs every 1 hour, 2-hour lookback, `arg_max` latest observed state per AgentId, inner-joined to Active `AIGS_M365CopilotBaseline` rows. Blank expected model/version disables per-property comparison.
- Added `AIGS-Hunt-CopilotAgentModelInventory`: observed-state inventory of all Copilot agents and distinct AI model bindings. Use output to populate `AIGS_M365CopilotBaseline` before enabling drift detection.
- Added `AIGS_M365CopilotBaseline` watchlist (schema: `ItemKey,AgentId,AgentName,ExpectedModelName,ExpectedModelVersion,AppHost,Status,BaselineOwner,LastReviewed,Notes`; `itemsSearchKey=ItemKey`; Template row only shipped).
- Added workbook Module C tiles: agent/model inventory and model drift against baseline (isfuzzy-guarded, missing-table safe).
- Rewrote PREREQUISITES Module C: documents observed-state detection basis, direct-KQL non-ASIM, GA connector ID (`MicrosoftCopilot`), baseline workflow, and explicit scope boundary (lifecycle operations not in this pass).
- Moved `AIGS-PA002-ContentFilterMissingModel` roadmap entry from module C to module A (GUID and path preserved; not built this pass).
- Connector verified GA: `connectorId=MicrosoftCopilot`, `CopilotActivity`, `availabilityStatus=1`, `isPreview=false`.

**Design basis:** Morpheus Module C Design Gate (`morpheus-module-c-design-gate.md`). Operation-dependent plugin/promptbook lifecycle detections remain roadmap-only pending column schema confirmation.

---

## v3.0.3-preview.1 — Agent 365 Preview Batch

**Release date:** 2026-07-22
**Release type:** Preview
**Scope:** Module B Agent 365 vertical slice and workbook reliability fixes

- Added two fail-closed `AgentsInfo` analytics rules: missing declared guardrails and approved-baseline version/platform drift.
- Added `AIGS-Hunt-AgentConfigurationDrift` and the `AIGS_ApprovedAgents` Watchlist.
- Added Agent 365 inventory coverage to the workbook and corrected the health query to use `AgentsInfo.Timestamp`.
- Repaired workbook KQL Unicode escape failures and reshaped executive KPIs for valid tile rendering.
- Added source validation that rejects unsupported KQL Unicode escapes and wildcard tile column mappings.
- Rejected the planned external-identity hunt and DLP-enforcement claim because current `AgentsInfo` documentation exposes neither a stable creator/tenant field nor external Purview DLP enforcement state.

---

## v3.0.1-preview.1 — Reference Batch

**Release date:** 2026-07-17  
**Release type:** Preview  
**Scope:** Reference implementation batch — Module A documentation and source validation foundation

> ⚠️ **Preview Release.** This release establishes the documentation, source validation, and CI foundation for the solution. It does **not** represent a fully deployable solution across all seven modules. Only Module A (Azure OpenAI / Foundry) is implemented in this reference batch. Modules B–G are designed and contractually specified but are not yet scaffolded as deployable content.

---

### What's New in v3.0.1-preview.1

**Documentation Foundation**

- `README.md` — Honest root overview: community solution, current reference-batch status, module matrix, ASIM applicability, Deploy to Azure button (pending package URL), response policy, and module graduation criteria
- `PREREQUISITES.md` — Per-module prerequisite matrix covering all seven modules: connectors, license requirements, table names, ASIM declarations, UAMI role assignments, Teams OAuth connection requirements, Security Copilot delegated-OAuth exception, retention defaults, content ingestion policy, and validation semantics
- `ReleaseNotes.md` — This file
- `CHANGELOG.md` — Machine-readable change log following [Keep a Changelog](https://keepachangelog.com/)
- `Playbooks/AIGS-Notify-001-TeamsAlert/readme.md` — Full specification: trigger, actions, UAMI permissions, Teams connector architecture, failure behavior, rollback scope (N/A — notification only)
- `Playbooks/AIGS-Auto-001-RestoreDiagnostics/readme.md` — Full specification: trigger, preconditions, approval model, timeout behavior, rollback, audit trail, failure handling

**Source Validation**

- `scripts/Test-AIGovernanceSource.ps1` — Native PowerShell source validator. Checks: JSON parse validity, YAML required fields (text-safe), unique GUIDs, forbidden hard-coded Azure IDs, Package generated-only contract, Watchlist CSV/JSON pair completeness, KQL ASIM declaration, documentation presence, and unexpanded placeholders. Fails clearly with per-check diagnostics.
- `.github/workflows/validate-ai-governance-solution.yml` — CI workflow: runs source validator on Windows runner; no unapproved third-party dependencies; exits non-zero on any failure

---

### Not Included in This Release

| Item | Status | Notes |
|------|--------|-------|
| Module A ARM templates (analytic rules, workbook, playbook Logic Apps) | 🔵 In progress | Tank/Neo authoring; Gate 1a validation pending |
| Modules B–G content files | 🔵 Designed | Not scaffolded; full design in `.squad/decisions/inbox/` |
| Solution package (`Package/`) | 🔵 CI-generated | Generated by `createSolutionV3.ps1`; not hand-authored |
| Deploy to Azure button | ⏳ Pending | Requires package generation and published release URL |
| Workbook JSON | 🔵 In progress | Trinity authoring |
| KQL analytic rules and hunting queries | 🔵 In progress | Neo authoring under corrected table contracts (Module A: `AzureActivity`) |
| Watchlist CSV and JSON metadata files | 🔵 In progress | Tank/Neo authoring |
| Custom parsers | 🔵 In progress | Neo authoring |
| AIGS-Enrich-001-SecurityCopilot playbook | 🔵 Designed | Module G; disabled by default; requires delegated-OAuth exception |

---

### Known Issues and Caveats

1. **Module A table correction applied:** All AIGS-CD001 and AIGS-AM001 KQL must target `AzureActivity` (not `AzureDiagnostics`). Content filter policy changes are ARM management-plane events — `AzureDiagnostics` does not carry them.

2. **`PurviewAuditLogs` is not a real table:** All Module F content uses `OfficeActivity | where OfficeWorkload == "Purview"`. The exact `Operation` values for Purview AI Hub policy events are not yet confirmed in published documentation — Module F rule (AIGS-AM002) is provisional until verified in the validation workspace.

3. **`AgentsInfo` is a Preview table** (replaces deprecated `AIAgentsInfo`): Module B content uses `AgentsInfo`. The previous table name `AIAgentsInfo` was deprecated 2026-07-01 and must not appear in any content.

4. **Module D rule scenario revised:** The original "Defender XDR AI Policy Configuration Drift" scenario relied on unverified `CloudAppEvents` ActionType values. The rule is revised to "Unsanctioned AI Application Access" (behavioral heuristic). Hunting queries remain the preferred surface for Module D until ActionType values are independently verified.

5. **Security Copilot UAL opt-in required:** Installing the Microsoft Copilot Data Connector alone does not populate `CopilotActivity` with Security Copilot events. The Security Copilot Owner must explicitly enable "Logging audit data in Microsoft Purview" in Security Copilot Owner settings.

6. **Deploy to Azure button pending:** The Deploy to Azure button requires a publicly accessible package URL. This will be added in the next release once the solution package is generated and a repository release is published.

---

### Validation Environment

- Validation workspace region: West US 2
- Tables confirmed present in validation workspace: `AzureActivity`, `AzureDiagnostics`
- Connectors confirmed in validation workspace: Azure Activity Logs (built-in); Office 365 connector (installed; `OfficeActivity` has 0 rows in last 7d)
- Gate 1b status: In progress
- Alert firing: Not required at any gate

---

### Framework Mappings

Controls in this release map to:
- Microsoft Cloud Security Benchmark (MCSB)
- NIST AI Risk Management Framework (AI RMF)

---

### Support

Community support via [GitHub Issues](../../issues). This solution is published by [x3nc0n](https://github.com/x3nc0n) and is not affiliated with or supported by Microsoft Corporation.
