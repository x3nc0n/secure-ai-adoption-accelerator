# Changelog — Microsoft Sentinel – AI Governance Solution

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Version numbers follow the V3 ARM contentPackages convention: `Version` in the source data manifest equals `_solutionVersion` in the generated package (write-back model). `contentSchemaVersion: 3.0.0` is the fixed ARM schema format version and is not the solution release version.

> **Package version reproducibility note:** The official `createSolutionV3.ps1` tool has no "no-bump" mode. Every `-VersionMode local` invocation increments the data file `Version` by the specified bump type and writes it back. To regenerate at the current version, reset the data file `Version` to N−1 before running. There is no officially supported way to regenerate a specific past version without this manual reset.

---

## [3.0.6-preview.1] — 2026-07-23

### Added
- Module E Azure General Preview vertical slice: AIGS-AM001 (unauthorized deployment), AIGS-Hunt-AIModelDeploymentChanges, and AIGS_ApprovedModels watchlist (shared with Module A).
- Workbook Module E tiles: deployment activity inventory and unauthorized finding surfaces (isfuzzy-guarded, missing-table safe).
- PREREQUISITES Module E rewrite: fail-closed baseline matching, ARM operation verification, composite deployment-name join key, no region/model-version/SKU enforcement, analyst ARM verification requirement, and scope boundaries explicitly documented.

### Changed
- Module Inventory datatable updated: Module E BatchStatus, ControlIDs, WatchlistDependency, and ControlCount reflect new content.
- Module Health ASIM table: verified AzureActivity native ASIM `imAuditEvent` for Module E.
- Solution Contents: 8 rules now includes Module E AIGS-AM001 attribution (previously showed "Module A has 2" without clarifying Module E shares rule); hunt count remains 7 (one per module).

### Removed
- Stale "pending Trinity evidence contract" language from Module E documentation (evidence contract now accepted; rule implemented and validator-approved).
- Stale "approved regions" language from Module E watchlist purpose (region enforcement unsupported by AzureActivity schema).
- Stale "hunting query for AI resources provisioned outside approved regions" claim (region enforcement out of scope).

### Fixed
- Module E documentation drift: status corrected from research/in-progress to Preview implementation; rule semantics, baseline workflow, and known limitations now documented with authoritative accuracy.

---

## [3.0.5-preview.1] — 2026-07-23

### Added
- Module C M365 Copilot Preview vertical slice: AIGS-CD003 (model drift), AIGS-Hunt-CopilotAgentModelInventory, and AIGS_M365CopilotBaseline watchlist.
- Workbook Module C tiles: agent/model inventory and model drift visibility (isfuzzy-guarded, missing-table safe).
- PREREQUISITES Module C rewrite: observed-state model binding drift detection, direct-KQL non-ASIM, GA connector, no lifecycle operation detections this pass.

### Changed
- Module Inventory datatable updated: Module C BatchStatus, ASIM label, ControlIDs, and WatchlistDependency reflect new content.
- Module Health ASIM table: CopilotActivity row updated from custom-normalization to N/A direct-KQL.
- AIGS-PA002-ContentFilterMissingModel roadmap entry reassigned from module C to module A (GUID and path preserved; not built this pass).
- Connector guide updated: Module C no longer lists Microsoft Defender XDR as required connector.

---

## [3.0.3-preview.1] — 2026-07-22

### Fixed — Formal Review Corrections (Morpheus — Lead Architect, 2026-07-17)

- `Data/Solution_AIGovernance.json` — Version corrected to `3.0.1` (V3 ARM write-back convention). An earlier revision incorrectly set this to `1.0.0`; the official `createSolutionV3.ps1` tool requires `Major ≥ 3` for contentPackages format and writes the incremented version back to the data file after each run. Canonical convention (confirmed against Microsoft Copilot reference solution): source `Version` = package `_solutionVersion`. Human-facing release label: `v3.0.1-preview.1`.
- `Analytic Rules/AIGS-CD001-ProtectedRAIPolicyModified.yaml` — LOW-5: clarified `itemsSearchKey` convention. `ItemKey` is the named watchlist search-index column; KQL match uses `AccountName + PolicyName` fields. Comment locations corrected at four points (description block + three KQL comment lines).
- `Hunting Queries/AIGS-Hunt-AIModelDeploymentChanges.yaml` — LOW-6: module label corrected `A → E` (Azure General / Model Governance). Tags updated: `Module-E`, `AzureGeneral`, `AzureActivity` (removed `Module-A`, `AzureOpenAI`, `Foundry`).
- `Workbooks/AIGovernanceSolution.json` — LOW-6 + LOW-7: all five occurrences of stale artifact name `AIGS-Hunt-AIModelDeploymentsOutsideApprovedRegions` replaced with `AIGS-Hunt-AIModelDeploymentChanges`. Module E header now references Module E only (not cross-tagged A+E). Module A header corrected: hunt count `2 → 1`; datatable `HuntCount` for Module A `2 → 1`; BatchStatus corrected from "2 rules + 2 hunts" to "2 rules + 1 hunt". Module E aggregation note added inline.
- `api-versions.md` — LOW-8: `Microsoft.CognitiveServices/accounts/raiPolicies` entry corrected to "read only (monitoring/investigation via GET)"; removed false claim that PB-AUTO-01 writes to raiPolicies.
- `README.md` — stale "(Module A has 2)" hunt count note removed; now reads "7 queries (one per module)" consistent with Module A = 1, Module E = 1.
- `Package/` — Regenerated via official `createSolutionV3.ps1 -VersionMode local -VersionBump patch`. All LOW-5 through LOW-8 fixes reflected. 10 resources (1 contentPackages + 7 contentTemplates + 2 Watchlists). `_solutionVersion: 3.0.1`. `contentSchemaVersion: 3.0.0` (ARM V3 schema — not the solution release version).

### Added

**Documentation foundation (Switch — Validation Engineer)**

- `README.md`: Community solution root overview. Covers: reference-batch status, module matrix (all 7 modules), ASIM applicability table, deployment parameters, response policy, governance framework mappings, and support channel. Deploy to Azure button explicitly marked pending until package URL is available.
- `Solutions/Microsoft Sentinel - AI Governance Solution/PREREQUISITES.md`: Per-module prerequisite matrix for all 7 modules. Covers: connectors, license requirements, table names, ASIM declarations, UAMI role assignments, Teams OAuth connection requirements (OAuth vs. webhook distinction), Security Copilot delegated-OAuth exception, Module G activation gate, metadata and content retention defaults, content ingestion advisory, and validation semantics (alert firing not required at any gate).
- `Solutions/Microsoft Sentinel - AI Governance Solution/ReleaseNotes.md`: Reference-batch release notes with honest scope declaration, known issues, and table correction index.
- `Solutions/Microsoft Sentinel - AI Governance Solution/CHANGELOG.md`: This file.
- `Solutions/Microsoft Sentinel - AI Governance Solution/Playbooks/AIGS-Notify-001-TeamsAlert/readme.md`: Full playbook specification: trigger (Sentinel incident), Teams connector OAuth architecture, UAMI (Sentinel Reader), adaptive card notification (no approval), failure behavior, rollback scope.
- `Solutions/Microsoft Sentinel - AI Governance Solution/Playbooks/AIGS-Auto-001-RestoreDiagnostics/readme.md`: Full playbook specification: trigger (Sentinel incident, CD-domain rules), preconditions, bi-directional approval model (Teams "Post adaptive card and wait"), 4-hour approval timeout (no auto-approve), rollback procedure, audit trail (incident comments), failure handling, circuit breaker.

**Source validation (Switch — Validation Engineer)**

- `scripts/Test-AIGovernanceSource.ps1`: Native PowerShell source validator. Nine validation checks: (1) JSON parse validity, (2) YAML required fields (text-safe), (3) unique GUIDs, (4) forbidden hard-coded Azure IDs, (5) Package generated-only contract, (6) Watchlist CSV/JSON pair completeness, (7) KQL ASIM declaration in analytic rule YAML, (8) playbook documentation presence, (9) no unexpanded placeholders. Fails with non-zero exit code and per-check diagnostics. No unapproved third-party dependencies.
- `.github/workflows/validate-ai-governance-solution.yml`: CI workflow. Runs source validator on Windows runner (`windows-latest`). Triggers on push and pull request to `main` and `dev`. Exits non-zero on any validation failure. Does not introduce third-party dependencies. Documents path for optional package-generation validation once `createSolutionV3.ps1` is available.

### Notes

- This release documents the full 7-module solution design but implements only the reference batch (Module A documentation and source validation foundation). Modules B–G are designed and contractually specified but are not yet scaffolded as deployable content.
- `Package/` is CI-generated via `createSolutionV3.ps1 -VersionMode local`. Source `Version` equals package `_solutionVersion` (write-back model). `contentSchemaVersion: 3.0.0` is the ARM V3 schema format version and must not be confused with the solution release version.
- All formal review corrections from the Morpheus Design Review are reflected (LOW-5 through LOW-8 plus Module A hunt count correction).
- Trinity verified module contracts applied: table corrections for Modules A, C, D, F, G; connector name corrections for Module G; ASIM declarations finalized.

---

## Legend

| Tag | Meaning |
|-----|---------|
| `Added` | New files, features, or content |
| `Changed` | Modifications to existing behavior or content |
| `Deprecated` | Features that will be removed in a future release |
| `Removed` | Removed features or content |
| `Fixed` | Bug fixes |
| `Security` | Security-related changes |

[Unreleased]: ../../compare/v3.0.6-preview.1...HEAD
[3.0.6-preview.1]: ../../releases/tag/v3.0.6-preview.1
[3.0.5-preview.1]: ../../releases/tag/v3.0.5-preview.1
[3.0.1-preview.1]: ../../releases/tag/v3.0.1-preview.1
