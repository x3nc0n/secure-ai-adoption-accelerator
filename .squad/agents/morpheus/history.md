# Project Context

- **Owner:** x3nc0n
- **Project:** Microsoft Sentinel AI Governance solution
- **Stack:** Sentinel solutions, KQL, ARM/Bicep-compatible content, Logic Apps, Microsoft security and AI platforms
- **Created:** 2026-07-16T17:01:37.788-07:00

## Revision History

### 2026-07-23 — Documentation Consistency Corrections (Morpheus)

**Task:** Correct current-state documentation to match deployed package 3.0.5 / preview label 3.0.5-preview.1 and Modules A–C shipped status. Ensure no stale `3.0.1`, Module C Preview/custom-parser, or plugin-lifecycle-as-shipped claims remain.

**Files modified:**
- `README.md` — 9 corrections: version strings (3.0.3 → 3.0.5 throughout), Module C status (🔵 Designed → ✅ Preview implementation), Module E status added, Module C ASIM (custom parser → N/A direct-KQL), Module C connector (Preview → GA), Customer Outcomes reorganized (plugin lifecycle → roadmap), Solution Contents updated (parser counts, rule attribution), Release History line updated.
- `Solutions/Microsoft Sentinel - AI Governance Solution/PREREQUISITES.md` — 6 corrections: Module A rules list (removed AIGS-AM001), Module E status (🔵 Designed → ✅ Preview research/implementation phase), Module E watchlist purpose (removed "approved regions"), Module E stale "shared with Module A" note removed, Module G ASIM (custom parser → N/A direct-KQL), Module G parser-deploy note removed.

**Decision document written to** `.squad/decisions/inbox/morpheus-documentation-consistency.md`.

**Verification:** All searches for stale claims (3.0.[1-3] version strings, Module C Designed status, AIGS_CopilotActivity_Normalized attributed to Module C, plugin lifecycle as shipped, approved regions in Module E, AM001 shared claim) returned zero matches. Documentation now reflects deployed state.

**Key learnings:**
1. **Version drift compounds across releases.** README lagged 2 releases. Header, status sections, and release-history line all require coordinated update when a new batch ships — a single version string refresh is insufficient.
2. **Module status icons are high-visibility signals.** Gap between 🔵 Designed and ✅ Preview is the difference between spec-only and code-shipped. Stale icons invite deployment of incomplete modules and mislead stakeholders on gating requirements.
3. **Connector GA vs. Preview distinction is critical.** Module C's connector changed mid-cycle; docs must reflect published status, not wishlist status. Affects license/deployment prerequisites and support maturity promises.
4. **"Shared" ownership language creates accountability ambiguity.** Saying AM001 is "shared with Module A" was imprecise and led to it appearing in Module A's rule list even after moving to Module E. Explicit single ownership ("Module E owned") is clearer. If cross-module rule reuse is ever needed, list once under the owner with explicit "also used by Module X" note.
5. **Parser non-existence must be stated, not implied.** Saying "no custom parser dependency" is clearer than "direct-KQL with no parser mentioned." Explicit negation ("N/A — Direct-KQL (no parser)") removes ambiguity. Implied absence can be misread as "coming later."
6. **Region/location claims require explicit telemetry proof.** The "approved regions" language in Module E was unsupported because AzureActivity contains no location data. Telemetry-unsupported claims are high-priority doc cleanup risks; they often get copied into KQL and cause silent data gaps.

**Status:** Complete. Ready for release with v3.0.5-preview.1 (Module C batch). Module E documentation updates (AM001 rule, Trinity evidence contract, version bump to 3.0.6-preview.1) deferred pending implementation gates.

### 2026-07-23 — Module E Implementation Finalization: Documentation Completion (Morpheus)

**Task:** Finalize documentation for now-implemented, validator-approved Module E content. Update README, PREREQUISITES, CHANGELOG, and ReleaseNotes for 3.0.6-preview.1 release.

**Files modified:**
- `README.md` — 6 corrections: version strings (3.0.5 → 3.0.6), Module E status (research/design → Preview implementation), release statement and history updated, Solution Contents rule attribution includes Module E.
- `Solutions/Microsoft Sentinel - AI Governance Solution/PREREQUISITES.md` — Complete Module E section rewrite: new Detection Scope subsection (fail-closed semantics, scope boundaries), expanded Data Source (operation exact, terminal status, ARM path), Watchlist semantics (ItemKey vs. composite join key), full Rule semantics (frequency, lookback, join behavior, baseline guards), Baseline Workflow (4-step discovery + population), Known Limitations (7 explicit limitations including analyst manual ARM verification).
- `Solutions/Microsoft Sentinel - AI Governance Solution/CHANGELOG.md` — New `[3.0.6-preview.1]` section: Added (rule, hunt, watchlist, workbook, PREREQUISITES rewrite), Changed (module inventory, health ASIM), Removed (stale pending/regions/model-version), Fixed (doc drift). Links updated to 3.0.6-preview.1.
- `Solutions/Microsoft Sentinel - AI Governance Solution/ReleaseNotes.md` — New `v3.0.6-preview.1 — Azure General Module E Batch` section with rule semantics, hunt workflow, watchlist reuse, workbook, PREREQUISITES rewrite, stale-claim removal, validator results. Prior releases preserved (cumulative).
- `.squad/decisions/inbox/morpheus-documentation-consistency.md` — Updated with final Module E completion record.

**Verification:** All stale-language searches returned zero matches (pending Trinity, approved regions, model-version enforcement, anti-join without context, 3.0.5-preview as current, Module E research status). All content counts updated. Implementation verified against AIGS-AM001 delivery (GUID 752bbac1-66ff-4bba-93f7-46a57bbd793d): fail-closed semantics, composite join key, CognitiveServices-only scope, analyst manual ARM verification, no region/model-version enforcement.

**Key learnings:**
1. **Fail-closed patterns are reusable templates.** Module C CD003 pattern (guarded leftouter + baseline-presence gate) adopted for Module E AM001 — eliminates fail-open risk and provides template for future modules.
2. **Analyst manual verification is a documented requirement, not a limitation.** Explicit "analysts must verify via ARM" sets correct expectations and is clearer than implied.
3. **Composite join keys require explicit documentation.** "ItemKey vs. detection join key" distinction surfaces the difference between search-index and data columns—often conflated, highest-risk source of silent bugs.
4. **Scope boundaries must be explicit, not implied.** "CognitiveServices only" + listing all out-of-scope (Azure ML, region, model-version, SKU, Properties, deletion, auto-remediation) prevents feature creep and misunderstood commitments.
5. **Stale "pending" language must be completely removed.** Once implementation is complete and validator-approved, hedging should be cut entirely — it undermines stakeholder confidence.

**Status:** Complete. Modules A–E have complete, honest documentation. Ready for release as 3.0.6-preview.1 Module E Preview Batch.

**Decision written to** `.squad/decisions/inbox/morpheus-module-e-design-gate.md`. **Verdict: APPROVE Trinity research start; HOLD Neo KQL until evidence contract accepted.**

- **Scope bounded to CognitiveServices.** MVP = `Microsoft.CognitiveServices/accounts/deployments/write`
  + `Success` on `AzureActivity` only. Azure ML / other providers are roadmap — their operation
  names are unverified and must not be invented. No region/location claim (AzureActivity has no
  location; ResourceGroup is not a region proxy; region needs Azure Resource Graph).
- **Hunt reused as-is; rule is different.** `AIGS-Hunt-AIModelDeploymentChanges` (left-outer,
  surface-all-when-absent) is correct for a hunt but its behavior MUST NOT be copied into the rule.
  `AIGS-AM001` must be **fail-closed** (CD003 pattern): inner/guarded-absence join to `Status=Active`
  `AIGS_ApprovedModels`; empty/Template baseline ⇒ zero findings; no bare `leftanti`/`!in`.
- **Model name is not observable.** Deployment name (from `_ResourceId`) is a **proxy only**; true
  model/version/SKU live in the ARM request-body Properties, undocumented in AzureActivity. Join key
  = composite `AccountName/DeploymentName`. Search key stays `ItemKey`; join key is a data column.
- **AM001 identity valid.** GUID `752bbac1-...793d` unchanged; graduate from `_roadmap` to resolved.
- **Cross-module ownership corrected.** AM001 is **Module-E-owned**, not "shared with Module A";
  PREREQUISITES currently mis-lists it under Module A and carries a stale "approved regions" hunt claim.
- **README drift surfaced (2 releases behind).** Header/status/release-history still say v3.0.1/v3.0.3
  while package is 3.0.5 and Module C shipped. Module C mislabeled `🔵 Designed` + "custom parser
  AIGS_CopilotActivity_Normalized" + "plugin lifecycle" — all stale; Module C MVP is direct-KQL
  model-binding drift, no parser. This batch must close the README gap, not just add Module E.
- **Gate discipline:** Neo blocked on Trinity's written+accepted AzureActivity evidence contract
  before any AM001 KQL. Switch fixtures must include anti-join, no-Success-filter, region, and
  invented-column fail cases plus a fail-closed empty-baseline assertion.

### 2026-07-23 — Module C Design Gate: Observed-State MVP over Operation Assumption (Morpheus)

**Decision written to** `.squad/decisions/inbox/morpheus-module-c-design-gate.md`. **Verdict: APPROVE (scoped MVP).**

- **Operation ruled unavailable for scheduled content.** The authoritative `CopilotActivity`
  schema page (24 columns, updated 2026-05-06) lists **no** `Operation` column; the 11 admin
  operation names live on a separate audit-log-activities page and are unproven to materialize
  as a queryable table column. All Operation/RecordType-literal detections (Trinity GO 1–3,
  Switch fixtures A/B, PREREQ plugin-add rule) demoted to roadmap.
- **Defensible MVP = observed-state expected-state comparison.** `AIGS-CD003 - M365 Copilot
  Agent Model Drift`: inner-join `CopilotActivity` observed `AIModelName`/`AIModelVersion` by
  `AgentId` to Active `AIGS_M365CopilotBaseline`. Mirrors Module B `AIGS-CD002` exactly. Uses
  only verified columns; no Operation.
- **Inner join replaces unverified `Workload` literal.** The customer-curated baseline is the
  scope boundary, so no `Workload =~ "M365Copilot"` string needs inventing — this **supersedes**
  Switch TC-C-005. Key architectural move: when a discriminator value is unverified, let a
  fail-closed inner join define scope instead of a fabricated literal.
- **AIGS-PA002 reassigned C→A** (Azure OpenAI content filter concern), GUID/roadmap status kept.
  New Module C rule GUID `72eb1408-...` via UUIDv5(namespace, "AIGS-CD003-CopilotAgentModelDrift").
- **Deliverables this pass:** 1 rule (CD003), 1 hunt (CopilotAgentModelInventory), 1 watchlist
  (AIGS_M365CopilotBaseline promoted), workbook Module C tiles (isfuzzy-guarded), PREREQ rewrite,
  validator E6 forbidden-column guard. No custom parser (non-ASIM, direct KQL).
- **Unresolved connector ID handled without fabrication:** ship isfuzzy-guarded + prerequisite
  comment; omit or allowlist-validate `requiredDataConnectors.connectorId`; Trinity owns
  confirming exact Content Hub ID as a GA blocker (not an MVP-deploy blocker).

**Key learning:** Prefer a fail-closed inner join against a customer-curated baseline over any
detection that depends on unverified enum/literal values from preview telemetry. It converts an
evidence gap into a bounded, deterministic, high-confidence control.

**Key learning:** Separate "documented on an operations reference page" from "materialized as a
queryable column in the ingested table." The two are routinely conflated for preview connectors
and are the highest-risk source of silently-wrong KQL.

### 2026-07-24 — Module E Review Revision: Hunt Terminal Filter + PREREQUISITES Clarifications (Morpheus, Acting for Neo)

**Task:** Apply reviewer-required fixes to hunt and PREREQUISITES for Module E. Reviewer rejection cycle: hunt terminal filter accuracy, ItemKey/join-key distinction, leftouter semantics clarity. Neo locked out; Morpheus performing revision.

**Files modified:**
- `Hunting Queries/AIGS-Hunt-AIModelDeploymentChanges.yaml` — 3 corrections: (1) Description updated to reference both "Success" and "Succeeded" terminal values (live-proven telemetry), (2) Query comments clarified for dual-value acceptance and explicit join-key distinction (ItemKey vs. composite data column), (3) Filter line changed: `ActivityStatusValue =~ "Success"` → `ActivityStatusValue in~ ("Success","Succeeded")` — reduces false-zero suppression from transient states (Start, Accepted).
- `Solutions/Microsoft Sentinel - AI Governance Solution/PREREQUISITES.md` — 4 corrections: (1) Version header line 3: `v3.0.5-preview.1` → `v3.0.6-preview.1`; "Last updated": 2026-07-23 → 2026-07-24, (2) Watchlists Used: ItemKey clarified as "Sentinel watchlist search-index column (for discovery)"; detection join key clarified as "composite data column (`AccountName + "/" + DeploymentName`)", (3) Rule semantics complete rewrite: replaced imprecise "inner join" with accurate "guarded left-outer join (not inner join)" pattern; added explicit join key specification; added `isempty()` absence detection logic; added approval-marker gate explanation; clarified fail-closed design (empty/template-only baseline → zero findings); added blank AccountName/DeploymentName disablement note.
- `.squad/decisions/inbox/morpheus-module-e-review-revision.md` — Created with detailed decision record, verification results, corrections summary, validator assertions.

**Verification:** Source validator (all 15 checks): **PASSED** (117 checks, 0 failures, 0 warnings). Critical validations:
- ✅ Hunt YAML parsed; terminal status set both values accepted
- ✅ PREREQUISITES version line reads `v3.0.6-preview.1`
- ✅ Watchlist ItemKey correctly identified as search-index column
- ✅ Module E evidence-contract gates all passed (Trinity v1 validation)
- ✅ Fail-closed guard and approval-marker pattern verified against content

**Validator alert:** Package-generation mismatch may persist until Tank regenerates with `createSolutionV3.ps1 -VersionMode local -VersionBump patch`. Source validator has passed; package generation is a deployment-phase gate (not a blocker). Hunt KQL change and PREREQUISITES clarification confirmed functionally correct; manifest artifacts may require Tank regeneration to reflect hunt YAML changes.

**Key learnings:**
1. **Live-proven telemetry values are authoritative.** Hunt initial design captured "Success" only; production telemetry proved "Succeeded" also terminal. Both must be accepted case-insensitively; single-literal filters create false-zero gaps.
2. **ItemKey vs. detection join key is the critical semantic distinction.** ItemKey = Sentinel watchlist search-index column (UI/discovery); detection join key = KQL data columns (rule/hunt detection logic). Conflating these creates silent data gaps and cross-account collision risks. Documentation must be explicit.
3. **"Inner join" vs. "leftouter" distinction is non-negotiable.** Inner join implies symmetric match requirement (both tables' presence necessary); guarded leftouter means outer table always matched, inner table may be absent (absence case handled by `isempty()` gate). The wrong join type inverts the fail-closed semantics.
4. **Approval-marker gate + empty-baseline guard are reusable fail-closed pattern.** When a baseline watchlist is absent or contains only Template rows (zero Active rows), the join produces zero matches; `isempty()` gate forces zero findings. This pattern has proven reliable for CD003 (Module C) and AM001 (Module E) — documented and ready for adoption by future modules (CD005, PA001, etc.).
5. **Baseline-seeding hunt behavior is preserved across terminal-filter change.** Hunt uses left-outer with surface-all-when-absent behavior (when watchlist missing, all events surface for baseline population); rule uses guarded leftouter with fail-closed behavior (when watchlist missing/empty, zero findings). This is intentional and correctly documented: hunts are discovery tools; rules are compliance gatekeepers.

**Status:** Complete. Hunt and PREREQUISITES now accurately reflect live-proven telemetry contract, critical semantic distinctions, and fail-closed design. Ready for Tank package regeneration and production deployment. All reviewer advisories resolved.

**Decision written to** `.squad/decisions/inbox/morpheus-module-e-review-revision.md`. **Verdict: APPROVED — all fixes verified.**

## Revision History

### 2026-07-17 — V3 Tool Constraint Resolution: Version Coherence (Morpheus)

**Context:** Follow-up source authorization to resolve the V3 tool constraint proven in the previous session.

**Official V3 tool evidence (confirmed from source code):**

| Parameter | Values | Source line |
|---|---|---|
| `-VersionMode` | `"catalog"` or `"local"` | `[ValidateSet("catalog","local")]` |
| `-VersionBump` | `"patch"` \| `"minor"` \| `"major"` | `[ValidateSet("patch","minor","major")]` |
| No-bump mode | **Does NOT exist** | `# Always increment the version...` comment in `GetLocalPackageVersion` |

**Write-back behavior (confirmed):**
`GetLocalPackageVersion` always increments, then: `$dataFileContent.Version = $incrementedVersion; Set-Content -Path $dataFilePath ...`
Source data `Version` = generated package `_solutionVersion` after any local mode run.

**Reference evidence (Microsoft Copilot solution in Azure-Sentinel checkout):**
- `Data Version: 3.0.2` = `Package _solutionVersion: 3.0.2` — they match exactly.
- This confirms: the official convention is source `Version` = package version (post write-back, not pre-run).

**Canonical version established: `3.0.1`**
- `Solution_AIGovernance.json` `Version`: `1.0.0` → `3.0.1` (write-back convention; matches generated package)
- Human prerelease label: `1.0.0-preview.1` → `v3.0.1-preview.1` (all docs updated)
- `contentSchemaVersion: 3.0.0` (ARM V3 schema format — unchanged, not the release version)
- Watchlist `BaselineVersion: 3.0.0` (CSV data field — unchanged, not the release version)

**Files changed:**
1. `Data/Solution_AIGovernance.json` — `Version: "1.0.0"` → `"3.0.1"`
2. `README.md` — `v1.0.0-preview.1` → `v3.0.1-preview.1` (3 occurrences)
3. `CHANGELOG.md` — Complete restructure: section `[1.0.0-preview.1]` → `[3.0.1-preview.1]`; Fixed section merged into release entry; semver claim replaced with V3 ARM convention note; reproducibility note added; Planned section updated
4. `ReleaseNotes.md` — `v1.0.0-preview.1` → `v3.0.1-preview.1` (2 occurrences)
5. `PREREQUISITES.md` — `v1.0.0-preview.1` → `v3.0.1-preview.1` (1 occurrence)

**Package:** No regeneration needed. Source `Version: 3.0.1` = package `_solutionVersion: 3.0.1` — they match.

**Reproducibility limitation (documented in CHANGELOG, reported not fixed in validator):**
The official tool has no "no-bump" mode. Every `-VersionMode local` run increments. To regenerate at the same version, one must manually reset the data file to N−1 before running. This is an inherent limitation of the tool's design, not a solution-specific issue. Documented in CHANGELOG header for operator awareness.

**Validator result:** 65 checks, 0 failures, 0 warnings. **PASSED.** Check 11 now shows: `Version '3.0.1' is a valid numeric three-part version` ✓

### 2026-07-17 — Package Regeneration + V3 Tool Constraint Discovery (Morpheus)

**Context:** Follow-up to formal review revision. Tank locked out. Morpheus regenerating Package as independent revision owner.

**V3 Tool Constraint Proven:**
The official `createSolutionV3.ps1` `returnContentResources()` function requires `Major >= 3` for contentPackages ARM schema format, or `Major == 2` for TemplateSpec format. For `Major == 1` (our previous `1.0.0` fix), the function returns null and the tool exits:
```
"Not able to identify content resource details based on Version. Please verify if Version in data input file is correct!"
```
This proves the constraint noted in the previous task: "Canonical generator version must be numeric 1.0.0 **unless official V3 tool proves a constraint**." The constraint is proven. The `Version` field in `Solution_AIGovernance.json` is NOT the solution's semantic version — it is the ARM schema version selector AND package version tracking field. It must remain `3.x.x`.

**Key architecture distinction (documented for follow-up correction):**
| Version Identity | Value | Location |
|---|---|---|
| ARM contentPackages schema version | `3.0.0` | `Solution_AIGovernance.json` "Version" (tool requires major >= 3) |
| Solution package version (generated) | `3.0.1` | `mainTemplate.json` `_solutionVersion` |
| Solution semantic version | `1.0.0` | Human docs only (README, CHANGELOG, ReleaseNotes) |

**Required follow-up (source revision, not Package):**
`Solution_AIGovernance.json` "Version" must be corrected from `1.0.0` → `3.0.0`. The previous revision incorrectly treated this field as a semantic version field; the V3 tool proves it is an ARM schema selector. This requires an authorized source revision by Neo or x3nc0n (Morpheus cannot edit source files in this task scope).

**Stale temp output prevented:**
Previous run's temp data file had `Version: "3.0.1"`. Reset to `3.0.0` before this run to prevent a `3.0.2` bump. Tool correctly bumped `3.0.0 → 3.0.1` in the temp copy, not the repo source.

**Generator command used:**
```
pwsh -NoProfile -NonInteractive -File createSolutionV3.ps1 \
  -SolutionDataFolderPath "<azure-sentinel-checkout>/Solutions/Microsoft Sentinel - AI Governance Solution/Data" \
  -VersionMode local -VersionBump patch
```
Temp solution tree synced from current repo source before run. Temp data `Version` overridden to `3.0.0` (V3 minimum) without touching repo source.

**Package artifacts generated:**
| File | Size | Notes |
|---|---|---|
| `mainTemplate.json` | 175,083 bytes | 10 resources (1 contentPackages + 7 contentTemplates + 2 Watchlists) |
| `createUiDefinition.json` | 19,687 bytes | Handler: Microsoft.Azure.CreateUIDef v0.1.2-preview |
| `testParameters.json` | 1,345 bytes | ARM parameter defaults for test automation |
| `3.0.1.zip` | 34,160 bytes | Canonical distribution zip; overwrote stale prior `3.0.1.zip` |

**Resource inventory (10 resources):**
- 1× Microsoft.OperationalInsights/workspaces/providers/contentPackages (solution package)
- 7× Microsoft.OperationalInsights/workspaces/providers/contentTemplates: 2 analytic rules, 2 hunting queries, 1 workbook, 2 playbooks
- 2× Microsoft.OperationalInsights/workspaces/providers/Watchlists

**Content verification:**
- `OutsideApprovedRegions` occurrences in package: **0** ✓ (LOW-7 fix reflected)
- `AIModelDeploymentChanges` occurrences in package: **7** ✓ (correct current name)
- `contentSchemaVersion` throughout: **3.0.0** ✓ (ARM V3 schema format)
- `_solutionVersion`: **3.0.1** ✓

**Validator result:** `scripts/Test-AIGovernanceSource.ps1 -PackagePath Package/`
→ 65 checks, 0 failures, 0 warnings. **PASSED.**

**Generator stderr noted:**
```
Warning: Could not update version in metadata file: SolutionMetadata.json. Error: The property 'version' cannot be found on this object.
```
Non-blocking. `SolutionMetadata.json` lacks a top-level `version` property; the tool attempted to set it but harmlessly skipped. All ARM content was generated correctly.

```
Error occurred in catch of createSolutionV3 file Error details are ... arm-ttk/download-arm-ttk.ps1 is not recognized...
```
The `arm-ttk` validation module is not installed in this environment. This is a POST-generation validation step only; `GeneratePackage` completed successfully before this error. All three JSON artifacts and the zip were written to the correct repo Package directory via `git rev-parse --show-toplevel` → `secure-ai-adoption-accelerator` repo root.

### 2026-07-17 — Formal Review Revision Continued: Stale Hunt Counts + CHANGELOG (Morpheus)

**Resumed from prior session. Additional corrections applied:**

**Files changed (this session):**
1. `Solutions/Microsoft Sentinel - AI Governance Solution/Workbooks/AIGovernanceSolution.json` — Module A datatable: `HuntCount` corrected `2 → 1`; `BatchStatus` corrected `"2 rules + 2 hunts"` → `"2 rules + 1 hunt"`. Moving `AIGS-Hunt-AIModelDeploymentChanges` to Module E (LOW-6) left a residual count inconsistency that was not caught in the prior pass.
2. `README.md` — "Solution Contents" table: stale "(Module A has 2)" hunt note removed; now reads "7 queries (one per module)".
3. `Solutions/Microsoft Sentinel - AI Governance Solution/CHANGELOG.md` — [Unreleased] `### Fixed` section added, documenting all six review corrections (LOW-5 through LOW-8, version identity, Module A hunt count).

**Validator result:** 64 checks, 0 failures, 0 warnings. PASSED.

**Package drift:** `Package/mainTemplate.json` retains `_solutionVersion: 3.0.1` / `contentSchemaVersion: 3.0.0`. This is expected and not a source error — Package is CI-generated and cannot be hand-edited. Regeneration via `createSolutionV3.ps1` is the only correct resolution.

**Canonical version semantics:**
- Machine-readable (manifest): `1.0.0` — in `Solution_AIGovernance.json` `"Version"` field only
- Human-facing prerelease label: `v1.0.0-preview.1` — in README, CHANGELOG, ReleaseNotes, PREREQUISITES
- `contentSchemaVersion: 3.0.0` in Package — this is the Sentinel *schema format* version (V3 ARM schema), not the solution version; it is correct and does not conflict

### 2026-07-17 — Formal Review Rejection: Cross-Artifact Version and Low-Severity Corrections (Morpheus)

**Reviewer lockout context:** Tank (manifest/package author) locked out of next revision. Morpheus assigned as independent revision owner for version consistency and low-severity cross-artifact corrections.

**Canonical version selected: `1.0.0`**
- Rationale: Initial community release. V3 generator is compatible with 1.0.0. The `3.0.0` in Solution_AIGovernance.json was an erroneous draft value. Preview status belongs in human release text (CHANGELOG, ReleaseNotes, README), not in the non-preview `Version` field. No verified V3 tooling constraint requires 3.0.0.

**Files changed:**
1. `Solutions/Microsoft Sentinel - AI Governance Solution/Data/Solution_AIGovernance.json` — Version: 3.0.0 → 1.0.0
2. `Solutions/Microsoft Sentinel - AI Governance Solution/Analytic Rules/AIGS-CD001-ProtectedRAIPolicyModified.yaml` — LOW-5: clarified that `itemsSearchKey` is `ItemKey` (named index column), KQL match uses `AccountName + PolicyName`; corrected four comment locations
3. `Solutions/Microsoft Sentinel - AI Governance Solution/Hunting Queries/AIGS-Hunt-AIModelDeploymentChanges.yaml` — LOW-6: Module label changed A → E (Azure General / Model Governance); tags updated to Module-E/AzureGeneral
4. `Solutions/Microsoft Sentinel - AI Governance Solution/Workbooks/AIGovernanceSolution.json` — LOW-6 + LOW-7: renamed stale `AIGS-Hunt-AIModelDeploymentsOutsideApprovedRegions` → `AIGS-Hunt-AIModelDeploymentChanges` (5 locations); re-labeled hunt as Module E artifact; aggregation note retained inline
5. `Solutions/Microsoft Sentinel - AI Governance Solution/api-versions.md` — LOW-8: corrected false claim that PB-AUTO touches raiPolicies; entry now says read-only (GET/monitoring only)

**Files not changed (no authorized source divergence found):**
- `guids.json` — already correctly has `"module": "E"` for AIGS-Hunt-AIModelDeploymentChanges; `searchKey: ItemKey` correct
- `README.md`, `CHANGELOG.md`, `ReleaseNotes.md`, `PREREQUISITES.md` — all use `v1.0.0-preview.1` as human release text; no change required

**Pending (awaiting package regeneration after playbook/readme revisions by Tank):**
- Package/ directory will temporarily drift until Tank's follow-up regeneration pass with createSolutionV3.ps1

**Validator run:** Source validator passed (JSON/YAML parse valid; no GUID uniqueness issues introduced; Package drift expected and noted — Check 12 not applicable until package is regenerated).


- Initial goal: detect AI configuration drift across Microsoft 365, Defender XDR, Agent 365, Microsoft Foundry, Azure, Security Copilot, and related services.
- Initial deliverables: analytics rules, hunting queries, at least one unified workbook, playbooks, packaging, tests, and documentation.

### 2026-07-16 — Architecture Discovery Assessment

- **Problem decomposition**: Five distinct governance functions identified (config drift, posture, audit, risky usage, incident response). Each needs different baselines and response models.
- **Critical dependency**: Drift detection requires an authoritative desired-state. No native "desired config" API exists for Azure OpenAI or Copilot Studio; must build config-snapshot polling + Watchlist comparison.
- **Licensing landscape**: Agent 365 ($15/user/month, E5 prereq) became mandatory July 1, 2026 for agent discovery/posture. `AIAgentsInfo` table deprecated → `AgentsInfo`. Security Copilot is consumption-based (SCU). Purview AI Hub requires E5 Compliance.
- **Telemetry tables confirmed**: AzureOpenAIServiceLogs (resource-specific, rolling out), CloudAppEvents (Defender XDR), AgentsInfo (Agent 365), UAL via Purview, AzureDiagnostics (legacy fallback).
- **Privacy constraint**: Purview UAL excludes prompt text by design. Azure OpenAI CAN log content if enabled. Solution must never enable content logging by default.
- **Key failure modes**: rules without populated baselines, schema changes in preview tables, alert fatigue from noisy config snapshots, stale watchlists.

### 2026-07-17 — Implementation Design Review Ceremony

- **Scope reconciliation**: Broad 7-module first release confirmed by user, reconciled with Neo's narrow-slice recommendation. Azure OpenAI/Foundry is reference implementation; remaining 6 modules follow the template.
- **Artifact manifest**: 42 authored files across 8 analytic rules, 7 hunts, 7 Watchlists, 2 parsers, 3 playbooks, 1 workbook (5 tabs), plus packaging/docs.
- **Ownership model**: Non-overlapping file ownership across 4 agents (Neo: 24, Tank: 8, Trinity: 1, Switch: 8). Morpheus holds review-only role.
- **Phased gates**: 3 acceptance gates — Gate 1 (reference module), Gate 2 (full solution), Gate 3 (deployment validation). Hard dependencies: Phase 2 blocked on Gate 1.
- **8 claims requiring verification**: Table schemas, operation names, ASIM parser coverage, and tooling compatibility must be validated before writing production KQL.
- **Deployment validation scope**: Deploy/wire/remove testing only; alert firing not required per user directive.
- **Key learning**: When reconciling narrow-vs-broad scope tensions, use a reference implementation pattern — one slice proves architecture while parallel work fills breadth. This prevents both "7 shallow placeholders" and "one slice with no roadmap."
- **Key learning**: Non-overlapping file ownership is the minimum viable coordination mechanism for parallel AI agent work. Merge conflicts are the primary throughput killer.
- **Key learning**: Claims about Sentinel table schemas must be verified against live workspace or official repo before any KQL is written. Schema assumptions are the highest-frequency cause of detection rule failures.
- **Novel detection categories identified**: agent-to-agent lateral movement, model version auto-upgrade drift, unauthorized plugin/connector addition, consumption anomaly (cost/abuse signal).
- **MVP boundary set**: Azure OpenAI + Copilot Studio + Security Copilot. Single-tenant. GitHub-distributed ARM. Watchlist-driven baselines.
- **Packaging**: Follow Azure/Azure-Sentinel solution structure (mainTemplate.json, createUiDefinition.json, SolutionMetadata.json). Use Create-Azure-Sentinel-Solution tooling.

### 2026-07-16 — Verified Corrections (Switch Review)

**Critical table name corrections applied:**
- ❌ `SecurityCopilotAuditLogs_CL` → ✅ **`CopilotActivity`** (native table via Microsoft Copilot CCP connector, not custom log)
- ❌ `AgentsInfo_CL` → ✅ **`AgentsInfo`** (Defender XDR native table, no `_CL` suffix; ALREADY LIVE with 30+ columns and 7+ hunting queries)
- ❌ `AzureOpenAIServiceLogs` (resource-specific) → ✅ **`AzureDiagnostics`** (filter by `ResourceProvider == "MICROSOFT.COGNITIVESERVICES"`)

**Stage prioritization correction:**
- ❌ Agent 365 `AgentsInfo` deferred to Stage 3 (weeks 13–20)
- ✅ Move `AgentsInfo` to **Stage 1/2 (weeks 1–12)** — table already live in official Azure-Sentinel repo with active hunting queries

**Minor corrections:**
- UAL retention terminology: "Standard/Premium" → **"E3/E5"**
- Watchlists folder: Not standard solution folder; document as custom addition for baseline management

**Evidence source:** Azure-Sentinel repo (SHA `29e1987d1015171e4c9687edfd31170902b59c7a`), Microsoft Learn (2026-07-16)

### 2026-07-16 — Remaining Defaults Resolution (Autonomous)

**Context:** User confirmed 18 architectural decisions in interactive walkthrough, then became unavailable during region selection. Instructed team to work autonomously and make good decisions.

**Approach:** Identified 20 remaining architecture/product decisions needed before implementation. Resolved all reversible defaults autonomously. Flagged 7 irreversible or cost-bearing decisions as gated for human return.

**Key defaults set (all reversible and parameterized):**
- **Region:** `eastus` default with mandatory service-availability preflight; always a deployment parameter.
- **Workbook personas:** 5-tab model (Executive Summary, SOC Operations, Platform Health, Compliance Mapping, Module Coverage) with persona-driven navigation.
- **Severity model:** 4-level severity (High/Medium/Low/Informational) × 3-level confidence (High/Medium/Low) with composite priority determining response path.
- **Module maturity:** 4-stage lifecycle (Experimental → Preview → GA → Deprecated); modules cannot skip Preview.
- **Control ID namespace:** `AIGS-<DomainCode><NNN>` with 5 governance domains (CD/PA/AM/RU/IR).
- **CI gates:** 8 blocking gates including ARM validation, KQL syntax, secret scan, GUID consistency, package generation, Watchlist schema, changelog, and reviewer approval.
- **Versioning:** SemVer from `1.0.0`; pre-release as `0.x.y`.
- **Branch strategy:** `main` (release), `dev` (integration), `feature/<name>`, `release/v<X.Y>`.
- **Approval timeout:** 4 hours default, escalate to email on timeout, never auto-approve.
- **Cost guardrails:** $25/day budget alert, consumption-plan Logic Apps, no SCUs unless explicitly testing Security Copilot module.
- **Unavailable services:** Surface as coverage gaps ("Not Configured" / "License Required"), deploy rules disabled, never show false-compliant.
- **GUID management:** Deterministic UUIDv5 from solution namespace + content ID for reproducibility.

**Gated for human return (irreversible/cost-bearing):**
Content Hub publication, upstream PR, production deployment, SCU provisioning, marketplace registration, external branding, production UAMI role assignments.

**Learnings:**
- Favor parameterization over opinions: every default is overridable at deployment time.
- Preflight checks are non-negotiable: region, connector, license, and table availability must all be validated before any resource creation.
- Coverage gaps must be visible, not hidden: "Not Configured" is always preferable to silent omission or false compliance.
- Composite severity × confidence matrices reduce alert fatigue more effectively than severity alone.
- Deterministic GUIDs (UUIDv5) prevent drift between builds and environments — critical for reproducible Sentinel solution packaging.
- Approval workflows must fail-safe: timeout should escalate, never auto-approve.
- Lab/validation cost guardrails prevent accidental spend, especially for consumption-based services like Security Copilot SCUs.

### 2026-07-23 — Module E Telemetry Acceptance Gate (AIGS-AM001) — ACCEPT

**Task:** Hard acceptance gate for Trinity v2 telemetry contract before Neo authors AM001 KQL.

**Independent live verification (isolated az config, tenant Spava Corp, workspace law-sc-westus2):**
- ARM Operations API confirms literal `Microsoft.CognitiveServices/accounts/deployments/write` (read/write/delete). This proves the RBAC/ARM operation — distinct from proving the Activity Log OperationNameValue.
- Live `AzureActivity` proves the OperationNameValue is emitted as `MICROSOFT.COGNITIVESERVICES/ACCOUNTS/DEPLOYMENTS/WRITE` (uppercase) — case-insensitive match mandatory. For that op: Success=193, Start=219, Failure=26.
- Table-wide status values include BOTH `Success` (49096) and `Succeeded` (408) — Succeeded is a real ARM terminal-success value.
- 193 success rows: `_ResourceId`/`Caller`/`CallerIpAddress` 100% populated; deployment name parsed on 191/193 (2 account-level writes) — rule must guard `isnotempty(DeploymentName)`.

**Key rulings (bound in acceptance contract, supersede looser v2 wording):**
- Terminal-success filter = case-insensitive SET `in~ ("Success","Succeeded")` — justified by official docs + live presence; strictly safe (both terminal, excludes transient Start/Accept).
- Join key = COMPOSITE `tolower(AccountName)+"/"+tolower(DeploymentName)`, NOT deployment-name-only. Deployment names are unique only within an account; deployment-only join is a false-negative vector.
- Fail-closed = guarded `leftouter` + `not(IsApproved)` under `ActiveBaselineCount > 0` scalar. Bare `leftanti`/`!in` prohibited (validator + design gate).
- MITRE tactics/techniques OMITTED — governance/compliance finding, not attack detection. Severity High/High retained.
- Foundry coverage scoped to CognitiveServices-provider accounts only; ML-hub Foundry excluded.
- Accepted with 4 non-gating Trinity doc corrections (latency/RBAC-catalog overclaim remnants, ASIM checkmark, terminal-success set, Foundry scoping).

**Learnings:**
- A successful live workspace query can convert an evidence gap into verified fact — I closed the exact gap Trinity honestly reported (her query failed; the isolated az config + `@file.kql` to preserve inner quotes worked; `az monitor log-analytics query` via variable strips inner double-quotes → SEM0062).
- ARM Resource Provider Operations API proves the operation/RBAC name; only a live `AzureActivity` query proves the Activity Log `OperationNameValue` literal + casing. Keep these two claims separate.
- Distinct-value live queries are cheap and high-leverage: they settled Success-vs-Succeeded and the account-level-write edge case that pure documentation could not.
- Composite (account+deployment) keys beat name-only keys wherever the child name is only locally unique — a recurring fail-closed correctness pattern for watchlist joins.
