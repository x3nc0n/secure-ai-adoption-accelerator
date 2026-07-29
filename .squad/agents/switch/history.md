# Project Context

- **Owner:** x3nc0n
- **Project:** Microsoft Sentinel AI Governance solution
- **Stack:** Sentinel solution validation, KQL tests, ARM templates, CI checks
- **Created:** 2026-07-16T17:01:37.788-07:00

## Learnings

### 2026-07-23T15:28:11-05:00: Module C Saved Workbook Instance — Deployed and KQL-Validated

**Authorized by:** x3nc0n (explicit confirmation)
**Artifact:** `.squad/decisions/inbox/switch-module-c-workbook-deployment.md`
**Proof:** `.azure/deployment-plan.md` (Validation Proof rows, workbook update block)

**What was done:**
- Overwrote the existing saved workbook resource `eb4c10d7-3884-4fe0-b3e3-f349ecd02f48` (`AI Governance Solution - law-sc-westus2`) with the approved Module C workbook definition from `Solutions/Microsoft Sentinel - AI Governance Solution/Workbooks/AIGovernanceSolution.json`.
- Preserved all required ARM resource properties (location=westus2, kind=shared, category=sentinel, sourceId, tags).
- Verified auth context (tenant `ef4ecf0b` / subscription `45da0317`) before write using isolated Azure CLI config.
- Confirmed serializedData round-trip: source 67,072 chars → readback 67,072 chars; revision `4a9db6112395444881953c18188cbca4`.

**Module C surface checks (all PASS):**
- Inventory tile (`M365 Copilot Agent Model Inventory`) ✅
- Drift tile (`M365 Copilot Agent Model Drift` vs. `AIGS_M365CopilotBaseline`) ✅
- `let modC = toscalar(union isfuzzy=true (CopilotActivity ...))` in health-modules query ✅
- GA connector wording (`Microsoft Copilot Data Connector (GA)`) ✅
- No `Operation` column in Module C KQL ✅
- No bad Unicode escape sequences ✅

**KQL parse validation: 19/19 PASS, 0 FAIL:**
- 5 datatable queries (exec-coverage, health-asim, compliance-mcsb, compliance-nist, modules-inventory) → returned rows, no errors.
- 10 live-table queries (AzureActivity, SecurityIncident, SecurityAlert) → parsed and returned clean 0–6 row results.
- 3 Module C `isfuzzy=true` queries (health-modules modC branch, modules-copilot-inventory, modules-copilot-drift) → returned 0 rows with no error. CopilotActivity absent behavior confirmed correct.
- `_GetWatchlist("AIGS_M365CopilotBaseline")` in drift query returned empty gracefully; `join kind=inner` on empty baseline → 0 rows. Fail-closed ✅.

**No alert/incident firing required.** Workbook is a read-only query surface; deployment does not create alerts.

**Key learning — ARM GET for workbooks requires `?canFetchContent=true`:** The default ARM GET for `Microsoft.Insights/workbooks` returns empty `serializedData`. Must append `canFetchContent=true` query parameter to retrieve the full workbook definition. This applies when reading back after any PUT or PATCH to verify content.

---



**Authorized files edited:** `scripts/Test-AIGovernanceSource.ps1`

**Check count:** 12 → 13. Existing 91 pass count (was 60 at Gate v2 baseline, grown as content was added). Run result: 13 checks, 91 passes, 0 warnings, **0 failures**.

**Extension E1 — Check 6 searchKey from guids.json:**
- Removed the hardcoded `itemsSearchKey == "ItemKey"` assertion.
- Check 6 now loads `$script:GuidsRegistry` (set in Check 3) and looks up each watchlist's declared `searchKey` from the registry (main body first, then `_roadmap`).
- Falls back to `"ItemKey"` if the watchlist is not registered.
- `AIGS_ApprovedCopilotPlugins` (searchKey: `"PluginId"`) will pass when deployed; the three current `ItemKey` watchlists continue to pass unmodified.
- guids.json registry loaded once (at script scope via `$script:GuidsRegistry`) and shared across Check 6 and Check 13 — no redundant I/O.

**Extension E3 — Check 13 (new): Roadmap Path Existence Gate:**
- Iterates `_roadmap.analyticRules`, `_roadmap.huntingQueries`, and `_roadmap.watchlists` in guids.json.
- For each entry with a `file`, `metadataFile`, or `dataFile` attribute: asserts the file does NOT exist on disk.
- Current run: 17 roadmap paths checked, none deployed prematurely. **PASS**.
- When Neo creates a file at a roadmap path without promoting the guids.json entry, Check 13 produces: `ROADMAP FAIL: _roadmap entry '<name>' has file deployed at '<path>' — promote guids.json entry to main body`.

**Extension E2 NOT implemented:** x3nc0n directed that Module C rules must NOT reference a custom parser directly; Module C queries `CopilotActivity` natively. The `AIGS_CopilotActivity_Normalized` parser mentioned in the planning document was from the earlier Morpheus manifest and is not part of Trinity's verified telemetry contract for Module C.

**Remaining gated items (require Trinity strict evidence or human decision):**
- E4 (UAL ingestion delay warning in Check 2) — deferred pending Trinity table-specific schema confirmation
- E5 (PB-ENRICH-01/PB-APPROVE-01 in KnownPlaybookMap) — deferred until Stage 2 playbook directories exist
- TC-C-013 connector ID verification — Trinity must confirm exact Microsoft Copilot Data Connector ID string
- TC-C-011 AIGS-PA002 module assignment — x3nc0n must declare Module A vs. Module C before Neo authors the file

---

### 2026-07-23T10:37:49-05:00: Validator Gate v4 — E4/E6/Connector + Regression Suite + Neo Content Validated

**Authorized files edited:** `scripts/Test-AIGovernanceSource.ps1`
**New file:** `scripts/Test-ModuleCChecks.ps1` (regression test, 10/10 assertions pass)

**Check count:** 13 → 14. Run result: **14 checks, 110 passes, 0 warnings, 0 failures** — including
Neo-authored AIGS-CD003, AIGS-Hunt-CopilotAgentModelInventory, and AIGS_M365CopilotBaseline.

**Extension E4 — UAL ingestion delay warning (Check 2):**
- Added inside Check 2's queryFrequency validation block.
- Uses `Get-YamlQueryBlock` helper (new shared function) to extract the KQL query block.
- If `queryFrequency < 60 min` AND query contains `\bCopilotActivity\b`: emits WARN.
- AIGS-CD003 uses `queryFrequency: 1h` (exactly 60 min) — at threshold, no warning fires. Correct.

**Extension E6 + Connector Allowlist — Check 14 (new):**
- Scopes to files where CopilotActivity appears in cleaned (non-comment, non-watchlist-block) KQL.
- 4-step KQL cleaning before column checks: strip comment lines → strip `_GetWatchlist` materialize
  blocks (line-scanner) → strip remaining `_GetWatchlist("...")` inline calls → check for token.
- **E6a:** 8 forbidden column names (`Operation`, `AccessedResources`, `UserKey`, `ItemName`,
  `PluginId`, `PluginVersion`, `PolicyName`, `ContentFilterStatus`).
- **E6b:** `LLMEventData\s*[\.\[]` dynamic field access.
- **E6c:** `AIGS_CopilotActivity_Normalized` parser reference (enforces E2 inverse).
- **Connector:** `connectorId:` in a CopilotActivity rule must equal `MicrosoftCopilot` if present;
  omission is allowed. Neo's AIGS-CD003 uses `connectorId: MicrosoftCopilot` — passes correctly.

**Regression test (`Test-ModuleCChecks.ps1`):**
- 4 fixture YAMLs: bad-columns (E6a + wrong connector), llmdata (E6b), parser-ref (E6c), good.
- 10 assertions including: forbidden-column detection, connector rejection, E4 warn at 30 min,
  `MicrosoftCopilot` acceptance, E6b/E6c detection, no false positives on clean rule, no false
  positive on `PluginId` in watchlist let-block (word-boundary + block-stripping both confirmed).
- **All 10 assertions pass.**

**TC-C-004/005 superseded:** `Operation` and `Workload` literal value assumptions were not confirmed
in Trinity strict evidence. Check 14 enforces column absence, not value correctness. Neo must not
author RecordType/Workload filters based on the planning-document fixture schema without new evidence.

**AIGS-PA002 module assignment:** Per Morpheus/x3nc0n direction, AIGS-PA002 is Module A roadmap.
`guids.json` still shows `module: C`. x3nc0n must correct before Neo authors the file. This remains
the only pre-authoring blocker.

**Neo content validated:** AIGS-CD003 (`connectorId: MicrosoftCopilot`, `queryFrequency: 1h`,
`ASIM: N/A`, no forbidden columns in KQL block — forbidden names appear in description/comments only,
correctly stripped by Check 14). AIGS-Hunt-CopilotAgentModelInventory and AIGS_M365CopilotBaseline
(7 passes from Check 6 searchKey/no-active-rows/ARM shape). All clean.

**Remaining open items:**
- E5 (PB-ENRICH-01/PB-APPROVE-01 KnownPlaybookMap entries) — deferred until Stage 2 playbooks authored
- AIGS-PA002 module assignment — x3nc0n decision required

---

### 2026-07-23T10:37:49-05:00: Module C Independent Reviewer Gate — REJECT (documentation-only)

**Verdict:** ❌ REJECT — 2 defects (1 hard block, 1 soft). Zero content defects in YAML/KQL.
**Artifact:** `.squad/decisions/inbox/switch-module-c-review-verdict.md`

**Validation runs:**
- Production validator: 14 checks, 110 passes, 0 warnings, **0 failures** ✅
- Module C regression: 10/10 assertions pass ✅

**Content findings — ALL PASS:**
- AIGS-CD003 KQL: all columns in Morpheus §5.7 allowlist; `isfuzzy` guard; fail-closed inner join;
  blank property guard (`isnotempty`); `arg_max` latest-state; `queryFrequency: 1h` / `queryPeriod: 2h`;
  `connectorId: MicrosoftCopilot` (Trinity GA-confirmed); ASIM: N/A; Account + CloudApplication entity mappings.
- Typed fixture traces: matching baseline=0, model drift=1, version drift=1, blank expected=0,
  template-only baseline=0, absent CopilotActivity=0 — all correct.
- AIGS-Hunt-CopilotAgentModelInventory: `isfuzzy` guard; §5.7 allowlist; no `Operation`; no watchlist dependency.
- AIGS_M365CopilotBaseline: Morpheus §5.1 schema; 0 Active rows; `itemsSearchKey: ItemKey`; rawContent parity.
- Workbook Module C tiles: `isfuzzy` guard; fail-closed drift tile mirrors AIGS-CD003 logic; `noDataMessage`.
- GUID registry: 3 new items promoted, `status: resolved`; AIGS-PA002 → module A; 15 roadmap paths clean.
- Package: 17 resources; mainTemplate `_solutionVersion: 3.0.5`; correct zip.

**Defects (documentation only):**
- **D1 (HARD):** `PREREQUISITES.md` says `v3.0.4-preview.1`; `ReleaseNotes.md` says `v3.0.4-preview.1`;
  actual manifest/package is `3.0.5`. Docs were not updated after the final packaging bump. Revision: **Tank**.
- **D2 (SOFT):** Workbook connector guide (line 759): `"Public preview; schema may change"` for Module C.
  Trinity confirmed GA (`availabilityStatus: 1, isPreview: false`). Revision: **Trinity**.

**TC-C-005 (Workload literal) — formally closed:** Morpheus §2 explicitly supersedes this requirement:
"the baseline inner join is the authoritative, evidence-safe scope boundary." No `Workload =~ "M365Copilot"`
literal is needed or safe to assume without schema proof. This decision stands.

**Key learning — documentation version lag:** The `createSolutionV3.ps1` tool auto-bumps the data
file version on every run. Human-facing docs (PREREQUISITES.md, ReleaseNotes.md) must be written
AFTER final packaging, not before. Pre-bump version labels in docs create version mismatches. For
future review cycles: confirm docs match `Data/Solution_AIGovernance.json "Version"` BEFORE signing off.

**Next cycle:** After Tank fixes D1 and Trinity fixes D2, re-run validator + regression + spot checks.
Expected result: APPROVE.

---

### 2026-07-23T10:37:49-05:00: Module C Reviewer Gate Cycle 2 — APPROVE

**Verdict:** ✅ APPROVE
**Artifact:** `.squad/decisions/inbox/switch-module-c-review-verdict.md` (Cycle 2 heading)

**D1 resolved (Tank):** All three version labels now say `v3.0.5-preview.1`:
- `PREREQUISITES.md` line 3 ✅
- `ReleaseNotes.md` heading ✅
- `CHANGELOG.md` heading → `[3.0.5-preview.1] — 2026-07-23` (was `[Unreleased]`) ✅
- Changelog history preserved: 3.0.3-preview.1 and 3.0.1-preview.1 intact ✅

**D2 resolved (Trinity):** Workbook connector guide Module C row updated to
`GA; schema stable (connector ID: MicrosoftCopilot)`. Zero "public preview" hits in any
content file. Workbook KQL tiles (`modules-copilot-inventory`, `modules-copilot-drift`)
confirmed unchanged — Trinity edited only the markdown text tile. ✅

**Unintended-change verification:**
- Neo content files: SHA256 prefix match confirms all unchanged (AIGS-CD003 `94D21B3AC4B0`,
  Hunt `19E88D69206C`, CSV `6B8FB9B82865`, WL JSON `0F1E4A1EB319`).
- guids.json `09019A1A3E2C`, mainTemplate `B7FD85A2C0B2` — unchanged.
- Workbook line count 782 (only connector guide text updated).

**Validators (Cycle 2):**
- Production: 14 checks / 110 passes / 0 warnings / **0 failures** ✅
- Regression: **10/10** assertions ✅

**Module C is APPROVED for Azure deployment and commit.**
Deferred gates remain: TC-C-014, TC-C-017 (Azure deployment), E5 (Stage 2 playbooks).



**Artifact:** `.squad/decisions/inbox/switch-module-c-validation-gates.md`

- **Module C gate is blocked on Trinity** until the Microsoft Copilot Data Connector ID string is confirmed (name verified, exact connector ID in Sentinel Content Hub catalog is not). Do not author `requiredDataConnectors:` with an unverified ID.
- **AIGS-PA002 module assignment is ambiguous** and must be resolved by x3nc0n before Neo authors the file. "ContentFilterMissingModel" sounds like Module A (AzureActivity/RAI policies) but is assigned `module: C` in `guids.json`. Wrong assignment means wrong connector prerequisite in the UI.
- **AIGS_ApprovedCopilotPlugins uses `PluginId` as searchKey**, not `ItemKey`. Check 6 in the current validator will hard-fail this watchlist. Extension E1 (read searchKey from guids.json) is required before Module C CI can go green on first run.
- **The `leftanti` antipattern is the #1 fail-open risk for Module C.** A query `| where ItemName !in (approvedPlugins)` against an empty approved list fires on every plugin event — the opposite of fail-closed. All Module C rules must use the inner-join + Active filter pattern established in Modules A and B.
- **CopilotActivity and AgentsInfo are both in preview and both absent from the validation workspace.** However, their failure modes differ: AgentsInfo is a snapshot table (empty = nothing to evaluate), CopilotActivity is an event stream (empty = no detections). Module C rules must explicitly handle the event-stream absence case; the workbook must show "no data" tiles, not errors.
- **Five validator extensions identified** (E1–E5): searchKey flexibility, parser dependency gate, roadmap path existence gate, UAL ingestion delay warning, and Stage 2 KnownPlaybookMap entries. E1–E3 are blockers; E4–E5 are improvements.
- **17 typed test cases defined**: 12 Hard (CI blocking), 3 Soft (warn), 2 Deploy (workspace required). Test fixtures include schema-verified datatable blocks for plugin lifecycle events, noise events, and watchlist states.

- Validation must cover official Sentinel solution schema and content conventions.
- Quality includes deployability, query correctness, performance, false-positive behavior, and documentation completeness.

### 2026-07-16: Discovery Phase Review

- **Table name verification is critical before any KQL authoring.** Three reports used different table names for the same data source. Verified: `CopilotActivity` (not `SecurityCopilotAuditLogs_CL` or `OfficeActivity`), `AgentsInfo` (not `AgentsInfo_CL`), `AzureDiagnostics` (not `AzureOpenAIServiceLogs`).
- **`AgentsInfo` is already live** in Defender XDR advanced hunting with 30+ columns and 7+ hunting queries in Azure-Sentinel repo. Do not defer to future stages.
- **`AIAgentsInfo` → `AgentsInfo` migration deadline is July 1, 2026.** Target `AgentsInfo` exclusively.
- **Solutions/README.md is the canonical certification reference.** Key rules: GUID `f1de974b-f438-4719-b423-8bf704ba2aef` required, "Azure Sentinel" banned, ReleaseNotes.md mandatory, version must match across manifest/metadata/package.
- **`AzurePolicyState_CL` has no evidence of existence.** Azure Policy compliance data requires custom ingestion.
- **SolutionMetadata.json `verticals` field is conventional, not required.** Present in Defender XDR, absent from Microsoft Copilot.
- **Watchlists/ is not a standard solution folder** per Solutions/README.md, but some solutions use watchlist content.
- **NRT rules require Analytics logs tier**, not a separate "NRT tier."
- **UAL retention**: 180 days (E3), 365 days (E5). Sentinel includes 90 days free interactive retention.

### 2026-07-16: Playbook Feasibility Review

- **Sentinel playbook triggers:** Only the incident trigger is GA. Alert trigger and entity trigger are both **Preview** (as of April 2026). Preview triggers cannot be attached to automation rules — manual execution only.
- **Security Copilot Logic Apps connector auth:** Only delegated OAuth (authorization code flow) is supported. Managed Identity and Client Certificate Auth are **not supported**. This means a licensed user account must own the connection.
- **Microsoft Graph has no `disableServicePrincipal` endpoint.** The correct operation is `PATCH /servicePrincipals/{id}` with `{ "accountEnabled": false }`.
- **Copilot Studio agent quarantine API** uses `POST /copilotstudio/environments/{envId}/bots/{botId}/api/botQuarantine/SetAsQuarantined` — not a generic PATCH. Requires Power Platform Admin or Global Admin role. GA since July 2025.
- **Azure diagnostic settings restoration** is idempotent and additive but not zero-risk: can overwrite existing configs, max 5 settings per resource, and may increase ingestion costs. Label as "low risk" not "zero risk."
- **Monitoring Contributor** is the correct built-in role for `Microsoft.Insights/diagnosticSettings/write`. Verified.
- **First-party playbook examples verified** in both `Azure/Security-Copilot` and `Azure/Azure-Sentinel` repos at the paths Tank documented. Authors confirmed.

### 2026-07-17: Content Value & Readiness Review

- **Verdict: NO CUSTOMER VALUE YET.** Zero product source files exist in the repository. All content is team scaffolding (Squad), decision documentation, and GitHub workflows for team operations.
- **Decisions ≠ deliverables.** 45 documented decisions are design-time intellectual property, not deployable content. Status language in `now.md` and `health-report` conflates decision completeness with implementation readiness.
- **Misleading status language identified:** "READY FOR IMPLEMENTATION" should be "DECISIONS COMPLETE — not yet started." Phase should be `pre-implementation`, not `implementation-planning`.
- **Broad first-release scope (7 platforms) contradicts module graduation criteria** and 4-week timeline. Recommended reduction to 2–3 domains at Preview+ maturity for v1.0.0.
- **Preview-enabled-by-default contradicts conservative posture** elsewhere in decisions. Recommended default to disabled.
- **Validation environment is the #1 unacknowledged blocker.** It is not gated (doesn't need approval) but it doesn't exist and no content can be validated without it.
- **ASIM claims are vacuous for core MVP tables** (`CopilotActivity`, `AgentsInfo`) which have no ASIM parsers. Only `AuditLogs` has ASIM coverage.
- **Immediate priority sequence:** (1) folder structure, (2) first KQL rule, (3) validation environment, (4) CI gate, (5) README, (6) scope reduction.
- **Key reviewer principle:** The first line of KQL committed is the first unit of customer value. Everything before it is preparation.
- **Review filed:** `.squad/decisions/inbox/switch-content-value-review.md`

### 2026-07-17: Design Manifest Review (Pre-Implementation Gate)

- **Verdict: APPROVE WITH CORRECTIONS.** 10 corrections required before full implementation proceeds; 2 high-severity (AIGS-CD002 unassigned rule, acceptance gates not separated per deployment-validation-scope directive).
- **Artifact count claims must be verifiable by tree enumeration.** Ownership sums and manifest tree counts must agree exactly. Three-way mismatches (38 tree / 41 ownership / 42 claimed) signal untracked files or double-counting.
- **Every file in the manifest tree must have a module assignment, table, and customer outcome.** Orphan rules (AIGS-CD002 in tree with no Section 2 entry) are architectural gaps, not minor omissions.
- **Custom normalization parsers ≠ ASIM promotion.** ASIM compliance means using `_Im*` functions that normalize into Microsoft-published schemas. Solution-specific parsers normalize for internal use and must not be claimed as ASIM-equivalent.
- **Acceptance gates must be explicitly split into CI-runnable (no workspace) and deployment-requiring (workspace).** The deployment-validation-scope directive is a binding user decision.
- **Phantom table names must not appear as primary references.** If a table doesn't exist as a Sentinel table (e.g., `PurviewAuditLogs`), use the actual table name with a filter clause, not the phantom name.
- **Module-to-rule naming must be internally consistent.** A filename describing "Token Consumption" cannot be assigned to a module detecting "Session Volume" — the disparity signals either a wrong assignment or a wrong filename.
- **Review filed:** `.squad/decisions/inbox/switch-design-manifest-review.md`

### 2026-07-16: Review of Morpheus Remaining Architecture Defaults

- **Autonomous default resolution is viable when user has explicitly authorized it**, provided: (a) every default is reversible and parameterized, (b) irreversible/cost-bearing items are gated for human return, (c) no tenant/subscription IDs are embedded, and (d) defaults align with prior human-approved decisions.
- **`tagEnvironment` default should be required, not `Production`.** Defaulting to `Production` during active development creates a tagging footgun — validation resources get misclassified. Either make it required or default to `Validation`.
- **Composite priority models (Severity × Confidence) must not imply auto-remediation.** The correct default response path for high-priority findings is notify + triage, not auto-remediate — consistent with the approved response policy.
- **"Coverage gap, never false-compliant"** is the correct principle for missing connectors/licenses. A five-condition behavior matrix (not configured / insufficient license / empty table / different region / preview unavailable) is a reusable pattern.
- **Module maturity labels must enforce "no skipping Preview."** Experimental → Preview → GA is the only valid graduation path.
- **CI gates should include GUID consistency checks.** Deterministic UUIDv5 with a `guids.json` registry and CI validation prevents GUID drift across builds.
- **Approval timeout must never auto-approve.** The correct default is escalate + log + leave incident in `New` status.
- **Review checklist for autonomous defaults:** reversibility, parameterization, least-privilege, no embedded IDs, alignment with prior decisions, irreversible items gated, naming consistency, no unverified assumptions treated as decided.

### 2026-07-17: Validator Strengthening (Gate v2)

**Authorized files edited:** `scripts/Test-AIGovernanceSource.ps1`, `.github/workflows/validate-ai-governance-solution.yml`

- **Check count expanded from 9 to 12.** New: Data Directory Structure (10), Manifest Completeness + Version + TemplateSpec (11), optional Package Validation (12).
- **Check 2 (YAML):** Added `kind:` to required rule fields. Scheduled rules now require `queryFrequency:` and `queryPeriod:`; both parsed as Sentinel durations and checked against 14-day duplicate-control threshold. Playbook cross-references in `Response:` lines mapped via `$script:KnownPlaybookMap` and verified to exist on disk.
---

### 2026-07-23T17:25:15-05:00: Module E Validator Gate v1 — Hunt/Watchlist Audit + Check 15 + Regression Suite

**Authorized files edited:** `scripts/Test-AIGovernanceSource.ps1`
**New files:** `scripts/Test-ModuleEChecks.ps1`, `.squad/decisions/inbox/switch-module-e-validation-gates.md`

**Check count:** 14 → 15. Run result: **15 checks, 111 passes, 0 warnings, 0 failures** — all existing Module A/B/C content clean.

**Independent Hunt Audit — `AIGS-Hunt-AIModelDeploymentChanges` (GUID `b4f2a8d1-..4d63`):**
- GUID, module (E), control (AM001 reference), connector (`AzureActivity`), `ActivityStatusValue =~ "Success"` filter, `tolower(OperationNameValue)` normalization — all ✅ PASS.
- No region/location predicate; Region column present in watchlist but explicitly not filtered (correctly documented) ✅.
- `kind=leftouter` + `WatchlistDeployed = toscalar(count() > 0)` scalar guard — correct surface-all-when-absent for hunt context ✅.
- Template-only baseline → WatchlistDeployed=false → all events surfaced (correct baseline seeding behavior) ✅.
- No invented columns; only documented AzureActivity fields used ✅.
- ASIM: `imAuditEvent — native (AzureActivity)` ✅.
- **One documentation note (non-blocking):** Hunt comment says "ModelId (searchKey)" — loose wording. Sentinel's actual index column is `ItemKey` (`itemsSearchKey`). The detection join key is `DeploymentName` (a data column). Comment-only issue; no functional defect.

**Independent Watchlist Audit — `AIGS_ApprovedModels` (GUID `1a4b8eea-..0d15`):**
- `itemsSearchKey: "ItemKey"` matches guids.json `searchKey: "ItemKey"` ✅.
- ARM template shape, all 12 CSV columns, rawContent/CSV parity, zero `Status=Active` rows (Template row only) — all ✅ PASS.
- `Region` column present but not used for filtering — correct per Morpheus §2.2 ✅.

**Check 15 (MODULE-E) implementation — 8 sub-checks, telemetry-independent:**
- **E7a:** FAIL if `ResourceLocation`, `ResourceRegion`, `DeploymentRegion`, or `ApprovedRegion` column used in KQL comparison (AzureActivity has no resource location — structurally false claim).
- **E7b:** FAIL if `ModelName`, `ModelFamily`, `ModelVersion`, `SkuName`, `SkuCapacity`, `ResourceLocation`, `ResourceRegion`, `DeploymentRegion` appear as KQL column references (model name/SKU not reliably observable from AzureActivity).
- **E7c-i/ii:** FAIL if Scheduled rule with AIGS_ApprovedModels uses `kind=leftanti` or `!in(...)` (fail-open against empty/Template-only baseline).
- **E7c-iii:** WARN if Scheduled rule with AIGS_ApprovedModels has no `toscalar` scalar gate.
- **E7c-iv:** WARN if Scheduled rule with AIGS_ApprovedModels missing `Status =~ "Active"` filter (Template rows included as approved).
- **E7d:** FAIL if Scheduled rule with AIGS_ApprovedModels reference and AzureActivity has no `ActivityStatusValue` filter (comment-stripped KQL; comment-only mention does not suppress failure).
- **E7e:** WARN if Scheduled AzureActivity rule has `queryFrequency` < 60 min.
- False-positive mitigations: comment stripping, watchlist materialize block stripping, column-comparison specificity (case() string literals with "region" text do NOT trigger E7a).

**Regression test (`Test-ModuleEChecks.ps1`) — 10/10 assertions pass:**
- E7c leftanti FAIL ✅, E7c toscalar WARN ✅, E7d ActivityStatusValue FAIL ✅, E7a region FAIL ✅, E7b ModelName FAIL ✅.
- False-positive guards: good hunt (no E7a from case() region strings) ✅, good rule (no E7c/E7d with correct pattern) ✅.

**Operation strings and field allowlists NOT hardcoded per Morpheus design gate:** Check 15 is deliberately telemetry-independent. The required operation string (`microsoft.cognitiveservices/accounts/deployments/write`) is not asserted as required — that assertion must wait for Trinity's evidence contract (EV-1 through EV-8 gated items in the decision doc).

**Gates still waiting on Trinity (evidence contract EV-1–EV-8):**
- Exact OperationNameValue and casing confirmation
- ActivityStatusValue terminal-success value confirmation
- `_ResourceId` ARM path extract pattern confirmation
- Model name/version/SKU non-observability confirmation (expected: NOT observable)
- Recommended queryFrequency/queryPeriod target values (ingestion latency)
- Multi-provider boundary (CognitiveServices only for MVP)
- Entity mapping column names (Account=Caller, IP=CallerIpAddress, AzureResource=_ResourceId) formal confirmation
- Connector/licensing (built-in, no connector)

**Key learning — fail-open anti-join is the highest-risk Module E pattern:**
`kind=leftanti` against a possibly-empty watchlist is structurally fail-open — if the watchlist is absent or has only Template rows, every AzureActivity deployment event fires as "unauthorized." This is the inverse of the desired fail-closed behavior. The Morpheus §5 pattern (leftouter + isempty(matchedKey) + toscalar WatchlistActive scalar gate) is the only safe approach. E7c-i makes this a hard FAIL at source gate, blocking it before any deployment.

---

### 2026-07-23T17:15:47-05:00: Module E Validator Gate v2 — Trinity Final Contract Binding

**Authorized files edited:** `scripts/Test-AIGovernanceSource.ps1`, `scripts/Test-ModuleEChecks.ps1`
**Decision doc updated:** `.squad/decisions/inbox/switch-module-e-validation-gates.md` (§10 added)
**Trigger:** Morpheus accepted Trinity's evidence contract with live AzureActivity proof.

**Contract bindings (EV-1 through EV-8 — all resolved):**
- **EV-1 operation:** `Microsoft.CognitiveServices/accounts/deployments/write` (case-insensitive, live-verified) → E7f: `cognitiveservices` required in comment-stripped KQL (use `$kqlForScanE`, NOT `$rawQueryBlockE` — see key learnings).
- **EV-2 terminal statuses:** Both `"Success"` and `"Succeeded"` confirmed in live AzureActivity table → E7d-ii WARN if only one literal found. `in~("Success","Succeeded")` is required in AM001.
- **EV-3 ResourceId parse:** Non-empty CognitiveServices account + deployment names → E7g: both `AccountName` and `DeploymentName` must appear in cleaned KQL.
- **EV-4 Properties prohibition:** Column exists but operation-specific subkeys not documented → E7b extended: `Properties.xxx`/`Properties[...]` access → FAIL.
- **EV-5 schedule:** `queryFrequency: 1h` / `queryPeriod: 4h` confirmed → E7k: warns on deviation from 1h/4h for ApprovedModels rules.
- **EV-6 scope boundary:** Azure ML out of scope → E7f catches missing scope implicitly.
- **EV-7 entity columns:** `Caller` (Account), `CallerIpAddress` (IP), `_ResourceId` (AzureResource) → E7h: all 3 entity types required when `entityMappings:` declared.
- **EV-8 connector:** AzureActivity built-in, confirmed. Already handled by Check 14.

**Gate v2 Check 15 sub-checks added:** E7d-ii, E7f, E7g, E7h, E7k (9 total sub-checks E7a–E7k).

**Regression test (Gate v2):** 11 fixtures / 16 assertions — **16/16 PASS** ✅.
Typed scenarios covered: both terminal statuses, cross-account deployment name, Properties access, deployment-only key, wrong schedule, incomplete entity mappings, false-positive guards for good hunt and good rule.

**Production validator results (Gate v2):**
- 15 checks / 114 passes / 0 warnings / 0 MODULE-E failures ✅.
- AM001 (`AIGS-AM001-UnauthorizedModelDeployment.yaml`) authored by Neo — passes ALL E7a–E7k gates.
- Check 13 FAIL: AM001 GUID not yet promoted in `guids.json` (Tank action — not Switch-owned).
- Module C regression: 10/10 PASS (no regressions from Gate v2 changes) ✅.

**Key learnings — Gate v2:**

1. **E7f must check comment-stripped KQL, not raw query block.** A fixture comment `// no cognitiveservices scope` contained the word "cognitiveservices." The E7f check against `$rawQueryBlockE` (which includes comments) matched the comment text and falsely suppressed the warning. Changing E7f to check `$kqlForScanE` (comment-stripped) fixed the false negative. Rule: any check looking for a required operational keyword must use comment-stripped KQL so advisory comments don't mask gaps.

2. **YAML entity-type regex must allow the list-item dash.** YAML Sentinel rule format is `  - entityType: Account`. The original pattern `^\s+entityType` required whitespace immediately before `entityType` and failed to match `  - entityType` because the dash is not whitespace. Fixed to `^\s*-?\s*entityType` which handles the optional `- ` list-item prefix. Lesson: YAML block sequences always use `- ` prefix before the first key in each map entry.

3. **E7k (schedule enforcement) must be scoped to ApprovedModels rules only.** AzureActivity Scheduled rules with other watchlists or no watchlists should not have 1h/4h enforced. E7k is correctly inside the `$refersApprovedModelsE` scope gate.

4. **Composite key is a security control, not just style.** Deployment-name-only joins cause cross-account false negatives: `gpt-4o` in account B is incorrectly treated as approved if `gpt-4o` appears in account A's baseline. The composite `tolower(AccountName) + "/" + tolower(DeploymentName)` key is required by the evidence contract. E7g makes this detectable at source gate.

5. **Single terminal status is a coverage gap, not a syntax error.** AzureActivity live table emits both `"Success"` and `"Succeeded"` for the same operation class. A rule using only `=~ "Success"` misses `Succeeded` events — real findings are missed. E7d-ii WARN makes this detectable without blocking (FAIL reserved for complete absence).


**Key learning — hunt vs. rule behavior distinction:**
A hunting query correctly uses surface-all-when-absent (WatchlistDeployed=false → show all events for baseline seeding). An analytic rule must be fail-closed (WatchlistActive=false → zero findings). These are opposite defaults serving different purposes. Check 15 E7c applies only to `kind: Scheduled` rules, not hunting queries, preserving this distinction.

**Key learning — comment-stripping is essential for E7d:**
The no-success fixture's comment line `// FIXTURE-E-003 — no ActivityStatusValue filter present (comment mentions it to test stripping)` contains "ActivityStatusValue." If Check 15 E7d checked the raw query block (including comments), the fixture would produce a false negative — the check would pass despite no actual filter. Using `$kqlForScanE` (comment-stripped) for E7d detection and `$rawQueryBlockE` (unstripped) only for the Status=Active filter check (which lives inside the materialize block) is the correct split.

---

- **Check 4 (Hardcoded IDs):** Expanded to scan `scripts/` directory. Self-exclusion for validator script (contains detection patterns). Watchlist exclusion broadened from `Data\Watchlists\` to all `\Watchlists\` paths.
- **Check 6 (Watchlist) rewritten:** Canonical format is ARM template at `Watchlists/<name>/<name>.json` (not old flat `Data\Watchlists\` metadata). Validates: ARM shape, Watchlist resource in `resources[]`, `itemsSearchKey == "ItemKey"`, `rawContent == CSV` (CRLF→LF normalized), CSV columns `ItemKey`+`Status`, no `Status=Active` baseline rows. Legacy `Data\Watchlists\` content flagged as requiring migration.
- **Check 9 (Placeholders):** Added `[PENDING_*]` bracket pattern. Expanded to scripts directory. Watchlist data files remain excluded.
- **Check 10 (NEW):** `Data/` must contain only JSON manifest files; `Data/Watchlists/` subdirectory flagged as misplaced. Solution-root `Watchlists/` asserted.
- **Check 11 (NEW):** Manifest path existence, Workbooks present, `Version` is `\d+\.\d+\.\d+`, `TemplateSpec == true`.
- **Check 12 (NEW, optional):** `-PackagePath` validates `mainTemplate.json` + `createUiDefinition.json` content; generator exit code alone is not sufficient.
- **CI workflow:** Added `package_path` input wired to `-PackagePath`. Documented separate package gate. No brittle network assumptions.

**Run result (2026-07-17T13:xx PDT):** 12 checks, 59 passes, 2 warnings, **4 genuine failures:**
1. `Bootstrap-AIGovernanceUami.ps1` — a session-local workspace name in .EXAMPLE
2. `Deploy-AIGovernanceValidation.ps1` — the same session-local workspace name in .EXAMPLE
3. `Bootstrap-AIGovernanceUami.ps1` — nil GUID as WhatIf PrincipalId placeholder
4. `Data/Solution_AIGovernance.json` — `TemplateSpec: false` (must be `true`) ← **RETRACTED — see correction below**

**Correction (2026-07-17T13:42 PDT):** Finding #4 was incorrect. Official solutions (Microsoft Copilot, Veeam) use `TemplateSpec: false`. The requirement was to validate the JSON *type* (boolean vs string), not mandate `true`. Check 11 updated to accept either boolean; a non-boolean would still fail. `TemplateSpec: false` is now a PASS.

**Corrected run result (2026-07-17T13:42 PDT):** 12 checks, 60 passes, 2 warnings, **4 failures:**
1. `Bootstrap-AIGovernanceUami.ps1` — a session-local workspace name in .EXAMPLE block
2. `Deploy-AIGovernanceValidation.ps1` — the same session-local workspace name in .EXAMPLE block
3. `Bootstrap-AIGovernanceUami.ps1` — nil GUID WhatIf PrincipalId placeholder
4. `Package/` directory exists with no README guard (Check 5 — new; Package/ was absent in prior run)

**Checks were NOT weakened to pass. Validator exits 1. Owner actions required before Gate 1a:**
- Tank: replace the session-local workspace name in script .EXAMPLE blocks with a generic name (for example, `law-yourworkspace`)
- Tank: replace nil GUID WhatIf placeholder with `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` format
- Tank: add `Package/README.md` with content "Do not edit — regenerate with createSolutionV3.ps1"

---

### 2026-07-23T12:49:01-05:00: Module C Azure Validation — Package 3.0.5

**Authorized actions:** Read-only ARM validate + what-if against rg-sc-logging-westus2; no deployment.

**Check count progression:** 14 checks, **112 passes**, 0 warnings, 0 failures (production validator with `-PackagePath`; +2 passes vs. Cycle 2 review's 110, reflecting `-PackagePath` enabling Check 12 sub-checks).

**Module C regression suite:** 10/10 assertions pass (E6a/b/c, connector ID, E4, false-positive guards).

**Key what-if insight — Module C adds 3 net-new resources:**
- `+ AIGS_M365CopilotBaseline` watchlist (Create)
- `+ contentTemplates/ar-*` (AIGS-CD003 analytic rule — Create)
- `+ contentTemplates/hq-*` (AIGS-Hunt-CopilotAgentModelInventory — Create)
- The existing AIGS content package updates from 3.0.3 → 3.0.5 (Deploy), along with 13 existing content templates (Deploy). 0 Deletes confirmed.

**What-if summary:** `3 Create, 14 Deploy, 13 Ignore, 0 Delete` — correct for a version bump of a deployed Sentinel content package.

**Learning: Version-bump what-if pattern for Sentinel content packages.** When an installed content package version is bumped, what-if will show the package + all existing templates as `Deploy` (idempotent update), and only new content as `Create`. Zero deletes confirms no regressions. This is the expected shape for an additive module graduation.

**ARM validation:** `az deployment group validate` → `Succeeded`, `error: null`. No parameter errors.

**Policy gate:** `az policy assignment list` → no assignments at subscription or RG scope. No policy blockers.

**RBAC gate:** `az role assignment list --resource-group rg-sc-logging-westus2` → no assignments at RG scope. Consistent with prior proof; UAMI runtime roles assigned at workspace scope only.

**TC-C-014 / TC-C-017:** Both deferred gates now addressable — what-if confirms template deploys cleanly with no active `CopilotActivity` data in workspace. Workbook missing-table render can be verified post-deployment.

**Verdict: VALIDATED.** Plan updated; status remains `Validated`.


---

### 2026-07-23T14:43:33-05:00: Module C Deployment — DEPLOYED (3.0.5)

**Verdict:** ✅ DEPLOYED
**Deployment name:** igs-module-c-3-0-5-deploy-20260723
**Duration:** PT6.5s (6.5 seconds)
**Artifact:** .squad/decisions/inbox/switch-module-c-deployment.md

**Pre-flight checks (immediate before deploy):**
- Plan status: Validated ✅
- Identity: jospaid@MngEnvMCAP643271.onmicrosoft.com / SC-Management 45da0317-4f5c-4be6-ae96-e8945b6f4c57 / tenant f4ecf0b-a160-444b-a405-ce3bf1f98752 ✅
- User confirmations: subscription, tenant, region, RG/workspace, 3.0.5 upgrade + 3 new Module C resources ✅
- Reviewer verdict: APPROVE (Cycle 2) ✅

**Deployment operations (17 Create + 1 EvaluateDeploymentOutput):**
- 1 contentPackages: x3nc0n.microsoft-sentinel-ai-governance-solution (updated 3.0.3 → 3.0.5)
- 12 contentTemplates: 5 AnalyticsRules + 4 HuntingQueries + 1 Workbook + 2 Playbooks
- 4 Watchlists: AIGS_ContentFilterPolicies, AIGS_ApprovedModels, AIGS_ApprovedAgents, AIGS_M365CopilotBaseline (all Succeeded Create)
- 0 deletes, 0 RBAC changes, 0 workspace/non-SecurityInsights operations

**Verification (all REST/CLI):**
- Package x3nc0n.microsoft-sentinel-ai-governance-solution version: **3.0.5** ✓
- Total AIGS content templates: **12** ✓
- AIGS-CD003 (72eb1408-feda-5533-a0fc-6d622e938011) → law-sc-westus2-ar-4zzhnyifvxrpw Kind:AnalyticsRule ✓
- AIGS-Hunt-CopilotAgentModelInventory (d6ddbee1-0c89-5d14-9902-501192433570) → law-sc-westus2-hq-l6owqaky72noa Kind:HuntingQuery ✓
- 4 watchlists present including AIGS_M365CopilotBaseline ✓
- AIGS_M365CopilotBaseline: itemsSearchKey=ItemKey, isDeleted=false, rawContent=0 bytes (template-only) ✓
- No unrelated resources changed or deleted ✓

**Saved workbook:** Content template for workbook is deployed (law-sc-westus2-wb-aecd3xxsgr23u). The existing **saved workbook instance** was NOT overwritten per task instruction — requires separate explicit user confirmation.

**Key learnings:**
- ARM deployment operations show all as "Create" even when what-if predicts "Deploy" for existing content templates. This is consistent behavior for Sentinel contentTemplates with deterministic resource names — each template resource is idempotently replaced via Create.
- A fresh clean-state deployment (all Create) is faster than what-if predicted (PT6.5s vs. PT5.8s Module B baseline). Difference within normal variance.
- The what-if 3 Create prediction exactly matched the 3 net-new Module C resources (AIGS_M365CopilotBaseline watchlist + AIGS-CD003 rule + AIGS-Hunt-CopilotAgentModelInventory hunt), confirming what-if accuracy.
- All 17 deployment operations completed without errors. ARM incremental mode with no deletes confirmed safe for additive solution upgrades.

**Plan status:** .azure/deployment-plan.md → **Deployed**


---

### 2026-07-24T08:21:52.393-05:00: Module E 3.0.6 Independent Reviewer Gate (Gate v3)

**Role:** Independent reviewer (Switch — Validation Engineer). Did not author Module E content, workbook, docs, guids, manifest, or package.
**Verdict:** ❌ REJECT — one blocking defect in hunt YAML
**Artifact:** `.squad/decisions/inbox/switch-module-e-review-verdict.md`

**Validator results (production tree):**
- `Test-AIGovernanceSource.ps1`: 117 passes / 0 warnings / 0 failures ✅
- `Test-ModuleEChecks.ps1` Gate v2: 16/16 assertions ✅
- `Test-ModuleCChecks.ps1`: 10/10 assertions ✅

**Scope items reviewed:** Git diff since ab6f221 (18 changed files), AM001 YAML KQL, hunt YAML KQL, watchlist interface, workbook JSON/KQL, README/PREREQUISITES/CHANGELOG/ReleaseNotes, guids.json, manifest, 3.0.6 package.

**BLOCKING DEFECT:**
- `Hunting Queries/AIGS-Hunt-AIModelDeploymentChanges.yaml` line 92: `ActivityStatusValue =~ "Success"` — single terminal status only.
- Trinity EV-2 confirmed both `"Success"` and `"Succeeded"` as terminal statuses for `Microsoft.CognitiveServices/accounts/deployments/write`.
- Workbook hunt tile was correctly updated to `in~ ('Success','Succeeded')`; the shipped YAML and its comment were not.
- Impact: Baseline-seeding via hunt produces incomplete inventory → AM001 detects `Succeeded` deployments not in baseline → false-positive unauthorized-deployment alerts.
- **Revision agent:** Morpheus. **Neo locked out** of this file until Morpheus's revision passes re-review.

**NON-BLOCKING (required in same PR):**
- `PREREQUISITES.md` header: `v3.0.5-preview.1` → `v3.0.6-preview.1` (stale; all other docs correctly show 3.0.6).
- **Revision agent:** Morpheus or Tank.

**Advisory (not blocking):**
- PREREQUISITES.md: `ItemKey` conflated with composite detection join key formula.
- PREREQUISITES.md: "inner join" label should be "guarded leftouter join."

**All other checks PASS:**
- AM001 KQL: all 10 typed fixture scenarios verified correct.
- AM001 contract compliance: EV-1 (operation exact match), EV-2 (both statuses), EV-3 (ResourceId parse + composite key), EV-4 (no Properties subkeys), EV-5 (1h/4h schedule), EV-6 (no Azure ML), EV-7 (entity mappings), EV-8 (AzureActivity connector).
- No region/model/version/SKU/Properties/AzureML/delete/unsupported-MITRE claims.
- Workbook JSON valid, 16 isfuzzy guards, AM001 SOC tile KQL correct (`in~`, composite join, fail-closed, arg_max dedup).
- Package: 3.0.6.zip present (48,992 bytes), 3.0.5.zip deleted, 18 resources (1 pkg + 13 templates + 4 watchlists).
- guids.json: AM001 promoted to main body, `status: resolved`, `module: E`.
- Secrets: no credential exposure. No unexpected changes.
- Module C intact: CD003 kind=inner, version 1.0.0, Module C regression 10/10.

**KEY LEARNINGS:**

1. **Hunt/workbook terminal-status divergence:** The workbook tile was updated during Gate v2 to use `in~("Success","Succeeded")`, but the corresponding hunt YAML was not updated. Content shipped as a batch must be reviewed for cross-file consistency, not just individual file correctness. When a multi-file operation (hunt → workbook) uses the same filter predicate, both files must be in sync.

2. **Check 15 E7d-ii scope gap:** E7d-ii (terminal status set check) was scoped to Scheduled rules only (`$isScheduledRuleE`). This means the hunt YAML's single-status filter at line 92 was NOT caught by the production validator. Future enhancement: extend E7d-ii scope to hunting queries, or add a new E7d-iii sub-check specifically for AzureActivity hunting queries that also need complete terminal status coverage.

3. **Reviewer divergence as signal:** When a workbook tile KQL and its source hunt YAML diverge on a contract-defined filter, the workbook is a useful "reference" and the YAML is likely the stale artifact. During review, comparing cross-file semantics is as important as per-file correctness.

4. **Documentation version header as last-line check:** PREREQUISITES.md version header was stale at base commit and was not bumped during the Module E batch despite content updates. A version-header consistency check (README vs CHANGELOG vs ReleaseNotes vs PREREQUISITES) should be added to the production validator or the packaging gate (Tank).

5. **Gate v3 confirmed no regressed work:** Gates v1 and v2 validator work (117 passes, Module E 16/16, Module C 10/10) remained fully green on the production tree under reviewer conditions. No regression from Module E content additions.


---

### 2026-07-24T09:08:02.650-05:00: Module E 3.0.6 Cycle 2 Re-Review — APPROVED

**Verdict:** ✅ APPROVE
**Artifact:** `.squad/decisions/inbox/switch-module-e-review-verdict.md` §8

**Cycle 1 REJECT resolution confirmed:**
- Hunt YAML line 92: `ActivityStatusValue in~ ("Success","Succeeded")` — both terminal statuses ✅
- Hunt comment block updated (line 55 area): both statuses documented, ItemKey vs. join key separated ✅
- PREREQUISITES.md line 3: `v3.0.6-preview.1` ✅
- PREREQUISITES advisory A3.1 (ItemKey/join-key): resolved with explicit separation in watchlist table ✅
- PREREQUISITES advisory A3.2 (inner join label): line 326 summary unchanged, but line 359 paragraph explicitly says "guarded left-outer join (not inner join)"; self-correcting within the section — acceptable for APPROVE

**Package regeneration verified:**
- mainTemplate hunt KQL: `ActivityStatusValue in~ (\"Success\",\"Succeeded\")` ✅
- 3.0.6.zip: 49,057 bytes (regenerated); 3.0.5.zip absent ✅
- 18 resources, `_solutionVersion: 3.0.6` ✅
- AM001 semantic invariants unchanged (in~, fail-closed, composite key, 1h/4h) ✅
- Hunt seeding invariants unchanged (WatchlistDeployed, leftouter, graceful degradation) ✅

**Validators:** 117/0/0 prod · 16/16 Module E · 10/10 Module C ✅

**KEY LEARNING — Cycle 2 package search pattern:**
When verifying that a packaged KQL matches the corrected source, do NOT use the content-template resource-name string as an anchor — it appears early in the JSON and the subsequent `ActivityStatusValue` match may come from a different resource. Instead, anchor on a **unique KQL variable** from the query body (`let LookbackPeriod` or `let DeployOp`) to find the exact hunt content section, then check `ActivityStatusValue` within that window.

**Neo lockout lifted:** Morpheus correction approved; Neo's lockout on `AIGS-Hunt-AIModelDeploymentChanges.yaml` released.

---

### 2026-07-23T20:40:00Z: Module E 3.0.6 Azure Validation — Local PASS, ARM BLOCKED (device-code auth)

**Role:** Switch (Validation Engineer) — azure-validate skill run against 3.0.6 package.
**Artifact:** `.squad/decisions/inbox/switch-module-e-azure-validation.md`, `.azure/deployment-plan.md` §11

**Context:** Post-Gate-v3-APPROVE azure-validate pass for Module E (3.0.6). Auth to SC-Management tenant `ef4ecf0b-a160-444b-a405-ce3bf1f98752` required in isolated `AZURE_CONFIG_DIR` (`.azcfg-validate`). User was not present to complete device-code flow during three attempts.

**Local gate results (all PASS):**
- Source/package validator: **15 checks, 119 passes, 0 warnings, 0 failures** (up from 117 — E7 checks expanded to 15-check set)
- Module E regression suite: **16/16 assertions PASS** (E7a–E7k, false-positive guards for good rule + good hunt)
- Package version/shape: `_solutionVersion: 3.0.6`, 18 resources (1 pkg + 13 contentTemplates + 4 watchlists), delta = +1 contentTemplate (AIGS-AM001)
- AIGS-AM001 GUID `752bbac1-66ff-4bba-93f7-46a57bbd793d` matches guids.json registry ✅
- 3.0.6.zip: 2 entries only (createUiDefinition.json 32.1 KB + mainTemplate.json 255.2 KB) — no extraneous files ✅
- Static RBAC: 0 roleAssignment resources, 0 identity blocks, 0 UAMI parameters — identical footprint to 3.0.5 ✅

**ARM gate results (all BLOCKED):**
- Three device-code login attempts in isolated dir `.azcfg-validate`; codes E6ESMAMAL, EX8P8NWNJ, FCHTFR6PG — all expired with `AADSTS70016: Authorization is pending` (user did not complete flow)
- ARM group validate: NOT RUN
- ARM what-if ResourceIdOnly: NOT RUN
- Zero-delete assertion: NOT ASSERTED

**Plan status:** `.azure/deployment-plan.md` remains `Deployed` (3.0.5). 3.0.6 not deployable until ARM validate + what-if (zero deletes) confirmed.

**Learnings:**

1. **Device-code auth in non-interactive sessions:** When Switch runs as a non-interactive sub-agent, device-code login requires the user to actively monitor the terminal output and complete the flow within the expiry window (~15 min per code). Three codes were generated but never completed. The pattern of multiple expiries without the user acting suggests the user ran the task asynchronously — Switch should surface the code prominently and wait with escalating polling, then stop and record the blocker rather than generating additional codes.

2. **Local-vs-ARM split validation pattern:** The 3.0.6 validation demonstrates a viable two-phase split: (a) complete all local gates (source validator, regression, static analysis) immediately, record them as PASS; (b) attempt ARM gates, record BLOCKED with exact commands needed to resume. This avoids total-failure reporting when only the auth step is missing.

3. **Source validator check count growth:** The production validator grew from 14 checks (3.0.5 era, 112 passes) to 15 checks (3.0.6 era, 119 passes). Check 15 (Module E AzureActivity contract gates) was added for E7a–E7k. This is expected growth as content modules ship.

4. **Isolated config dir naming:** The standard isolated Azure CLI config dir for this project is `.azcfg-validate` at the repo root. Use `$env:AZURE_CONFIG_DIR = ".azcfg-validate"` or the full absolute path. Do NOT use TEMP or system temp dirs — stay in the repo root per the project's security/environment requirements.

---

### 2026-07-29T09:27:17-05:00: Module E 3.0.6 Azure Validation Restart — Local PASS, ARM BLOCKED (device-code auth, 4th attempt)

**Role:** Switch (Validation Engineer) — clean restart of stale validation run; azure-validate skill.
**Prior stale agent stopped.** All prior proof preserved.
**Artifact:** `.azure/deployment-plan.md` §11 "3.0.6 Validation Restart — 2026-07-29"

**Context:** Restart requested by x3nc0n after previous run remained stale. Session at `.azcfg-validate` had expired auth. New device-code flow initiated; code `B6GHMCHPC` at https://login.microsoft.com/device — expired with `AADSTS70016` (user did not complete in ~15 min window). Fourth total expiry across all attempts.

**Local gate results (all PASS — confirmed stable, 4th consecutive clean run):**
- Source/package validator: **15 checks, 119 passes, 0 warnings, 0 failures** ✓ (2026-07-29T09:30:00-05:00)
- Module E regression suite: **16/16 assertions PASS** — E7a–E7k, false-positive guards ✓ (2026-07-29T09:31:00-05:00)
- Package version/shape: `_solutionVersion: 3.0.6`, 18 resources (1 contentPackages + 13 contentTemplates + 4 Watchlists) ✓
- 3.0.6.zip: 2 entries (createUiDefinition.json 32.1 KB + mainTemplate.json 255.2 KB) ✓
- Static RBAC: **0 roleAssignment resources, 0 identity blocks, 0 UAMI parameters, 0 Microsoft.Authorization resources** — all 18 resources are Microsoft.OperationalInsights Sentinel content; no RBAC footprint ✓

**ARM gate results (BLOCKED — 4th expiry):**
- Device code `B6GHMCHPC` expired without user completion
- ARM validate: NOT RUN; ARM what-if: NOT RUN; zero-delete assertion: NOT ASSERTED
- Plan status: remains `Deployed` (3.0.5)

**Key learnings:**

1. **Persistent auth blocker pattern:** Four consecutive device-code expirations across multiple sessions indicate this validation cannot complete without the user being present at the terminal during the auth window. The user must be ready to visit https://login.microsoft.com/device and enter the code within 15 minutes of Switch issuing it.

2. **Resume recipe:** Once user is ready to complete auth, run:
   ```
   cd C:\Users\jospaid\.source\GitHub\secure-ai-adotpion-accelerator
   $env:AZURE_CONFIG_DIR = ".azcfg-validate"
   az login --use-device-code --tenant ef4ecf0b-a160-444b-a405-ce3bf1f98752
   # Complete code at https://login.microsoft.com/device, THEN immediately re-invoke Switch
   ```
   After auth, Switch needs only to run ARM validate + what-if (both commands documented in deployment-plan.md §11). All local gates have passed four times; no re-run needed.

3. **Validate only what needs it:** Local gates are stable (same 119/15/16 results on every re-run). Future restarts should skip local gates if `.azure/deployment-plan.md` already shows them PASS for the same package hash, saving ~5 min per run.

---

### 2026-07-29T09:55:00-05:00: Module E 3.0.6 Azure Validation — COMPLETE PASS ✅

**Role:** Switch (Validation Engineer) — ARM gates completed after coordinator completed isolated device-code auth.
**Artifact:** `.azure/deployment-plan.md` §11 "3.0.6 Validation Restart — 2026-07-29"

**Context:** Coordinator completed device-code auth to tenant `ef4ecf0b-a160-444b-a405-ce3bf1f98752` in `.azcfg-validate`. Switch resumed immediately. SC-Management subscription required an explicit `az account set` before running ARM commands (active subscription was a personal sub; correct sub selected by ID).

**ARM gate results (all PASS):**
- `az account show`: SC-Management / `45da0317-4f5c-4be6-ae96-e8945b6f4c57` / tenant `ef4ecf0b-a160-444b-a405-ce3bf1f98752` / `jospaid@MngEnvMCAP643271.onmicrosoft.com` ✓
- `az deployment group validate`: **Succeeded; error: null** ✓
- `az deployment group what-if --result-format ResourceIdOnly`: **1 Create, 17 Deploy, 13 Ignore, 0 Delete** ✓
- Zero-delete hard guardrail: **0 Deletes — SATISFIED** ✓
- What-if Create: `contentTemplates/law-sc-westus2-ar-rke6ax5o7zj6c` = AIGS-AM001-UnauthorizedModelDeployment (Module E net-new) ✓
- What-if Deploy: 1 contentPackage + 12 contentTemplates + 4 Watchlists (all existing 3.0.5 resources updated) ✓
- What-if Ignore: 3 DCRs, 2 workbooks, 2 UAMIs, 1 workspace, 2 OMSolutions, 2 Web/connections — all unrelated, none modified ✓
- Static RBAC cross-check: both UAMIs (`mi-sc-westus2`, `uami-security-logging`) in Ignore list — not touched ✓

**Plan status:** Updated to `Validated (3.0.6)`. Ready for azure-deploy.

**Key learnings:**

1. **`az account set` required after device-code login:** After login to a multi-subscription tenant, the active subscription may default to a personal or first-listed subscription rather than the target. Always explicitly `az account set --subscription <id>` and verify with `az account show` before running any ARM commands.

2. **3.0.6 what-if signature:** `1 Create / 17 Deploy / 13 Ignore / 0 Delete`. The single Create is AIGS-AM001 (Module E). The 17 Deploys are all existing 3.0.5 resources receiving the version bump. The 13 Ignores are non-AIGS workspace resources. This is the expected baseline for any 3.0.6 deployment against the current 3.0.5 state.

3. **Validation complete:** After four restart cycles (local gates: 4× PASS; ARM gates: 1× PASS on this run), 3.0.6 is fully validated. All gates green, zero-delete confirmed, RBAC footprint unchanged.
