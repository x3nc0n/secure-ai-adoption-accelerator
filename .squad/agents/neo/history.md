# Project Context

- **Owner:** x3nc0n
- **Project:** Microsoft Sentinel AI Governance solution
- **Stack:** KQL, Sentinel Analytics Rules, Hunting Queries, Workbooks, solution metadata and packaging
- **Created:** 2026-07-16T17:01:37.788-07:00

## Learnings

- Content must conform to the official Microsoft Sentinel GitHub repository's current solution requirements and schema.
- The initial solution needs analytics rules, hunting queries, and at least one integrated workbook.

---

## Session: 2026-07-17 — Content Value Audit

**Objective:** Inventory actual product content, map decisions to customer outcomes, assess scope vs. graduation depth, define a validated vertical slice, and determine creation order.

### Key Findings

1. **Zero deployable product files exist.** The repository contains only squad infrastructure (`.squad/`), squad-scoped GitHub Actions, and Copilot skills. No `Solutions/` folder. No YAML, no JSON, no ARM templates, no watchlist CSVs — nothing deployable.

2. **Broad 7-platform scope conflicts with module graduation criteria.** Graduating 7 modules simultaneously requires 7+ analytic rules, 7+ hunting queries, 7 workbook modules, and 7 response guidance artifacts before any module ships. This is not a realistic first sprint.

3. **Recommended vertical slice: Azure OpenAI Content Filter Enforcement (AIGS-CD001).** Uses `AzureDiagnostics` (confirmed GA), deterministic Watchlist-based detection, validates the full pipeline (connector → KQL → entity → incident → playbook), and produces a real finding a CISO recognizes.

4. **13 artifacts define the minimum shippable slice.** In order: folder structure → SolutionMetadata.json → manifest skeleton → watchlist CSV → analytic rule YAML → hunting query YAML → 2-tab workbook JSON → PB-NOTIFY-01 → PB-AUTO-01 → ReleaseNotes/CHANGELOG → PREREQUISITES.md → package generation → Sentinel CI/CD.

5. **Twelve acceptance criteria.** Nine require a live validation workspace. All 12 must pass before the slice is called production-ready.

6. **Declared remaining 6 platform modules Experimental** until AOAI module graduates to Preview.

### Decision Filed
`.squad/decisions/inbox/neo-content-value-audit.md`

---

## Session: 2026-07-16 — Sentinel Solution Schema Research

**Objective:** Research official Azure-Sentinel solution conventions, schemas, tooling, and comparable solutions to produce an implementation-readiness assessment.

### What I Found

**Canonical folder structure** (verified in Azure/Azure-Sentinel master branch):
```
Solutions/<SolutionName>/
  Analytic Rules/       ← YAML source (hand-authored, one file per rule)
  Hunting Queries/      ← YAML source (hand-authored)
  Workbooks/            ← JSON source + Images/ subdir
  Playbooks/<Name>/     ← azuredeploy.json + readme.md + images/ per playbook
  Data Connectors/      ← JSON: ConnectorDefinition, DCR, PollingConfig (if CCP)
  Parsers/              ← YAML (if custom parser/KQL function needed)
  Data/                 ← Solution_<Name>.json content manifest (hand-authored)
  Package/              ← GENERATED: mainTemplate.json, createUiDefinition.json, *.zip
  SolutionMetadata.json ← Hand-authored publisher metadata
  ReleaseNotes.md       ← Required; must be present or PR is rejected
```

**Key schemas verified**:
- Analytic Rule YAML required: `id` (GUID), `name`, `description`, `severity`, `status`, `requiredDataConnectors[]`, `queryFrequency`, `queryPeriod`, `triggerOperator`, `triggerThreshold`, `tactics[]`, `relevantTechniques[]`, `query`, `entityMappings[]`, `version`, `kind` (Scheduled|NRT)
- Hunting Query YAML: same minus `queryFrequency/Period/trigger*` fields
- `Data/Solution_<Name>.json` manifest: `Name`, `Author`, `Logo`, `Description`, `Data Connectors[]`, `Analytic Rules[]`, `Hunting Queries[]`, `Workbooks[]`, `Playbooks[]`, `BasePath`, `Version`, `Metadata` (path to SolutionMetadata.json), `TemplateSpec` (bool)
- `SolutionMetadata.json` required: `publisherId`, `offerId`, `firstPublishDate`, `providers[]`, `categories.domains[]`, `support{name,email,tier,link}`

**Package generation model**:
- Tool: `Tools/Create-Azure-Sentinel-Solution/V3/createSolutionV3.ps1` (local) OR `.script/package-automation/package-generator.ps1` (CI)
- Generator reads `Data/Solution_<Name>.json` manifest, ingests all source YAML/JSON, emits `Package/mainTemplate.json` and `Package/createUiDefinition.json`
- `Package/*.zip` = versioned archive; file name must match `Version` field
- **Never hand-edit Package/** — doing so causes the GitHub integration workflow to reject or overwrite

**CI/CD validation gates** (GitHub Actions):
- `arm-ttk-validations.yaml`: Runs ARM TTK test suite on all `Package/mainTemplate.json` and `Package/createUiDefinition.json` in PRs
- `hyperlinkValidator.yaml`: Validates all hyperlinks in solution files
- `checkPRContentChange.yaml`: Detects which solution changed and routes to correct packaging workflow
- `solutionIntegration.yaml`: Triggers post-merge integration on `Package/mainTemplate.json` changes

**Version consistency requirement**: Version must match across Partner Center, `SolutionMetadata.json`, `Data/Solution_<Name>.json`, and `Package/mainTemplate.json`. PR will be rejected if mismatched.

**Certification gate (Sentinel GUID)**: Search keyword `f1de974b-f438-4719-b423-8bf704ba2aef` must appear in the solution offer.

### Comparable Solutions Identified

| Solution | Why Relevant | Key Patterns |
|---|---|---|
| [Microsoft Copilot](https://github.com/Azure/Azure-Sentinel/tree/master/Solutions/Microsoft%20Copilot) | Exact match: M365 Copilot + Security Copilot audit logs via Office Management API. CCP connector pattern. | ConnectorDefinition + DCR + PollingConfig JSON trio; `CopilotActivity` table; analytic rules on jailbreak/plugin tampering |
| [Microsoft Defender XDR](https://github.com/Azure/Azure-Sentinel/tree/master/Solutions/Microsoft%20Defender%20XDR) | Full-featured solution with MITRE-organized analytic rules, hunting queries, workbooks, playbooks | Tactic-based subdirectory organization within Analytic Rules/; playbook per-folder with azuredeploy.json + readme |
| [Microsoft Defender for Cloud](https://github.com/Azure/Azure-Sentinel/tree/master/Solutions/Microsoft%20Defender%20for%20Cloud) | Posture/recommendation analytics; SecurityRecommendation table usage | Posture-oriented detection patterns |
| [Microsoft Defender for Cloud Apps](https://github.com/Azure/Azure-Sentinel/tree/master/Solutions/Microsoft%20Defender%20for%20Cloud%20Apps) | Cloud governance/CASB posture workbook | Workbook + analytic rules composition |
| [Microsoft 365 Audit General and DLP](https://github.com/Azure/Azure-Sentinel/tree/master/Solutions/Microsoft%20365%20Audit%20General%20and%20DLP) | CCP-based data ingestion from M365 Management APIs (exactly our pattern for audit data) | Multiple CCP connectors with separate `_ConnectorDefinition.json` files |

### Open Schema Questions
- `TemplateSpec: false` in manifest: Determines whether V2 or V3 ARM template output is produced. Need to confirm which is required for Content Hub submission vs. private deployment.
- Data connector type for Azure AI Foundry / AOAI diagnostic logs: No native Sentinel connector exists; must use DCE/DCR custom log ingestion or Azure Diagnostics → LAW. CCP is not suitable for ARM diagnostic log routing — use `azurediagnostics` or `AzureOpenAIServiceLogs_CL` approach.
- `AgentsInfo` table: Still in preview (July 2026); must use `_IsBillable` guard and document preview status in connector.
- Workbook format: `.json` exported from Azure Portal Monitor Workbooks editor — NOT hand-authored. Must include `metadata.source.kind: community`.

### Files Worth Copying Structurally (not content)
- `Solutions/Microsoft Copilot/Data/Solution_MicrosoftCopilot.json` → our manifest skeleton
- `Solutions/Microsoft Copilot/SolutionMetadata.json` → our metadata skeleton
- `Solutions/Microsoft Copilot/Analytic Rules/CopilotJailbreakAttempt.yaml` → analytic rule YAML structure
- `Solutions/Microsoft Defender XDR/Analytic Rules/AVSpringShell.yaml` → entityMappings pattern
- `Solutions/Microsoft Copilot/Hunting Queries/CopilotExternalIPAccess.yaml` → hunting query YAML structure
- `Solutions/Microsoft Defender XDR/Playbooks/AttackSimulatorTrainingNonReporters/` → playbook folder structure

---

## Session: 2026-07-17 — Contract Corrections (x3nc0n directive)

**Objective:** Apply all corrections from x3nc0n's content review directive against four
authorized files: AIGS-CD001, AIGS-CD005, AIGS-Hunt-AzureOpenAIRAIChanges, and the
Outside-Approved-Regions hunt. Inputs: `switch-corrected-implementation-contract.md`,
`trinity-verified-module-contracts.md`, and `decisions.md`.

### Changes Made

#### AIGS-CD001-ProtectedRAIPolicyModified.yaml

1. **Fail-closed baseline gate**: Replaced `leftouter` join + `WatchlistDeployed` fallback with
   `inner` join on AccountName, followed by `| where PolicyTarget == WL_PolicyName` (ItemKey match).
   Empty or no-Active watchlist → inner join yields zero results. No graceful degradation for
   analytic rules.

2. **ItemKey documented and used**: `WL_PolicyName = tolower(PolicyName)` is the ItemKey
   (itemsSearchKey) column. Match now requires both AccountName and PolicyName to match an Active
   baseline entry. Previous version joined only on AccountName.

3. **queryPeriod**: `1d` → `1h` (matches queryFrequency; eliminates repeated 24-hour alert
   windows where each run covered the prior full day).

4. **Response guidance corrected**: Removed `PB-AUTO-01 (approval-gated restoration)` from
   description and note. AzureActivity does not carry before-state policy body; restoration
   without known prior state is unsafe. Guidance is now: PB-NOTIFY-01 (notify/investigate only).

5. **DriftFlag simplified**: Removed `INFO — Watchlist not deployed` and
   `LOW — Resource not in baseline` cases (never reached with inner join). Remaining cases:
   HIGH (Delete), MEDIUM (Write).

6. **DriftCandidateNote updated**: Explicitly states PB-AUTO-01 cannot restore this policy and
   directs analyst to REST API for current state.

7. **customDetails**: Removed `BaselineMonitored` (no longer projected; always true post-join).

#### AIGS-CD005-AIResourceDiagnosticsChanged.yaml

1. **Fail-closed baseline gate**: Added `ApprovedResources` load from
   `AIGS_ContentFilterPolicies` (Status=Active, AccountName → `WL_AccountName`). Inner join on
   AccountName scopes rule to approved AI resource set. Empty watchlist → zero results.

2. **Baseline scope rationale documented**: AIGS_ContentFilterPolicies does not define expected
   diagnostic settings values; it is used for resource scoping only (AccountName field).

3. **queryPeriod**: `1d` → `1h` (matches queryFrequency).

4. **Response guidance corrected**: Removed `PB-AUTO-01 (approval-gated restoration)`.
   AzureActivity lacks the before-state settings body; no baseline-safe restore is possible.
   RemediationNote updated to direct analyst to PB-NOTIFY-01 and manual investigation.

5. **SeverityIndicator updated**: Labels now reference "Active baseline resource" for clarity.

#### AIGS-Hunt-AzureOpenAIRAIChanges.yaml

1. **ASIM declaration made explicit**: Updated description ASIM line to:
   `native AzureActivity → imAuditEvent (_Im_AuditEvent, ASIM Audit Event schema);
    optional imAuditEvent mapping available. No custom parser required; no false ASIM claim.`

2. **Baseline-unavailable note added**: Added explicit paragraph stating this hunt does not
   assess compliance and that without AIGS_ContentFilterPolicies watchlist, no baseline
   comparison is performed — results are change evidence only, never compliance determination.

#### AIGS-Hunt-AIModelDeploymentsOutsideApprovedRegions.yaml → AIGS-Hunt-AIModelDeploymentChanges.yaml

1. **File deleted and replaced**: Old file (`AIModelDeploymentsOutsideApprovedRegions.yaml`)
   deleted; new file (`AIModelDeploymentChanges.yaml`) created with preserved UUID
   `b4f2a8d1-6e3c-4b9f-d0a7-8c2e5b1f4d63`.

2. **Name corrected**: `"AIGS - Hunt - AI Model Deployment Changes"` (region overclaim removed).

3. **Location limitation documented**: Description and KQL both explicitly state that AzureActivity
   does not contain resource location; region enforcement requires Azure Resource Graph correlation
   outside Sentinel KQL. ResourceGroup is NOT a reliable region proxy.

4. **Region comparison removed from KQL**: `AM_Region` column removed from `ApprovedModels`
   projection and from the `project` output. The watchlist's Region column is documented as
   reference-only in the comment.

5. **ApprovalStatus corrected**: `IN-BASELINE` case no longer references region; replaced with
   "verify model version. NOTE: location validation requires Azure Resource Graph."

6. **Tags updated**: Removed `ApprovedRegions` tag; kept `ModelDeployment` and other relevant tags.

7. **Baseline-unavailable note added**: Description explicitly states hunt does not assess
   compliance and that results are change evidence only when watchlist is absent.

8. **ASIM declaration made explicit**: Updated to match standard format with no-false-claim note.

### Telemetry Limits and Remaining Notes

- **AzureActivity lacks before/after policy body**: CD001 and CD005 alerts remain drift
  candidates only. Analysts must retrieve current state via REST API or Azure Portal. This is
  a fundamental telemetry limitation; no KQL workaround exists without supplemental snapshot data.

- **Region validation unavailable in Sentinel KQL alone**: The renamed hunt correctly documents
  that region compliance requires Azure Resource Graph correlation. Any future region enforcement
  analytic rule must use Resource Graph data ingestion or a supplemental resource snapshot.

- **CD005 diagnostic settings values not in baseline**: AIGS_ContentFilterPolicies tracks accounts,
  not expected diagnostic log categories or workspace destinations. A future AIGS_DiagnosticSettings
  watchlist would be required before CD005 can compare expected vs. actual settings values.

- **ASIM declarations**: All four files now have explicit ASIM status with `no false ASIM claim`
  wording per Trinity contract. Native AzureActivity → imAuditEvent is the only ASIM promotion
  in use across these files.

### Decision Filed
`.squad/decisions/inbox/neo-contract-corrections-2026-07-17.md`


**Schema & table name corrections:**
- ❌ `AzureOpenAIServiceLogs` as confirmed resource-specific table → ✅ **NOT CONFIRMED** (current evidence shows only `AzureDiagnostics` exists)
- ⚠️ `verticals` in SolutionMetadata.json: noted as conventional, NOT required (verified absent from Microsoft Copilot SolutionMetadata)
- ⚠️ Workbooks "portal-export-only" → ✅ **"portal-export recommended"** (not enforced by tooling)
- ⚠️ NRT tier language → ✅ **Clarified:** NRT requires Analytics logs tier (standard), NOT separate pricing tier

**Schema migration alert:**
- ❌ `AIAgentsInfo` → ✅ **Document migration to `AgentsInfo` (deadline July 1, 2026)** as schema stability risk for Stage 1/2 content

**Evidence source:** Azure-Sentinel repo (SHA `29e1987d1015171e4c9687edfd31170902b59c7a`), Microsoft Learn (2026-07-16)


---

## Session: 2026-07-23 — Module C Implementation (M365 Copilot Vertical Slice)

**Objective:** Author and package the Module C vertical slice per Morpheus design gate.

### What Was Built

1. **`AIGS-CD003-CopilotAgentModelDrift.yaml`** (GUID `72eb1408-feda-5533-a0fc-6d622e938011`):
   Fail-closed scheduled analytic rule. Materializes Active AIGS_M365CopilotBaseline rows, inner-joins
   CopilotActivity (isfuzzy-guarded with typed fallback) via normalized AgentId, selects latest observed
   state via arg_max(TimeGenerated, *) by AgentId, and fires when observed AIModelName or AIModelVersion
   differs from approved. Blank expected values disable per-property comparison. queryFrequency: 1h,
   queryPeriod: 2h. requiredDataConnectors: MicrosoftCopilot (verified GA).

2. **`AIGS-Hunt-CopilotAgentModelInventory.yaml`** (GUID `d6ddbee1-0c89-5d14-9902-501192433570`):
   Observed-state inventory hunt. Summarizes distinct AI model names, versions, and host applications
   per AgentId/AgentName/Workload over 14d. No watchlist dependency. No Operation references.
   isfuzzy-guarded with typed fallback.

3. **`AIGS_M365CopilotBaseline`** watchlist (GUID `855b82c3-e9fe-416a-ad0f-41db79f6433b`):
   CSV columns: `ItemKey,AgentId,AgentName,ExpectedModelName,ExpectedModelVersion,AppHost,Status,
   BaselineOwner,LastReviewed,Notes`. itemsSearchKey=ItemKey. Template row only shipped.

4. **Workbook updates**: Added M365 Copilot Agent Model Inventory tile and Model Drift tile to Module
   Coverage tab. Updated Module Inventory datatable, Module Health tile, and ASIM applicability table.
   All tiles use isfuzzy=true with typed fallback.

5. **guids.json**: Promoted AIGS-CD003, AIGS-Hunt-CopilotAgentModelInventory, and AIGS_M365CopilotBaseline
   to main body with status:resolved. Moved AIGS-PA002 from module C to module A in _roadmap (GUID and
   path preserved). Updated AIGS-Hunt-UnauthorizedPluginAccess roadmap status with blocker reason.

6. **Solution_AIGovernance.json**: Version bumped to 3.0.5 (per generator write-back). New analytic
   rule, hunting query, and watchlist wired in.

7. **PREREQUISITES.md**: Module C rewritten from scratch. Explicitly documents: observed-state model
   binding drift detection basis; direct-KQL non-ASIM; GA connector (connectorId=MicrosoftCopilot);
   baseline workflow; Operation column roadmap boundary.

8. **Package v3.0.5**: Generated via createSolutionV3.ps1 from Azure-Sentinel checkout (tool lives at
   Azure-Sentinel/Tools/Create-Azure-Sentinel-Solution/V3/). 17 resources: +1 analytic rule, +1 hunting
   query, +1 watchlist vs previous 3.0.3.

### Validation Result
Source validator: **14 checks, 112 passes, 0 warnings, 0 failures** (including Check 12 package
validation with 17-resource mainTemplate.json). ARM TTK 4 existing failures are pre-existing
empty-property issues unrelated to Module C content.

### Key Learnings

- **Package generator requires path with "Solutions" at index > 0**: The generator parses the path
  to find `Solutions`, derives `$repositoryBasePath` as everything before it, then looks for
  `Tools/Create-Azure-Sentinel-Solution/common/commonFunctions.ps1` relative to that base. Running
  from the Azure-Sentinel repo checkout with `./Solutions/...` path resolves all dependencies
  correctly. Alternatively, copy the solution to Azure-Sentinel checkout temporarily, run, copy
  Package back.

- **Generator bumps version before writing**: `-VersionMode local -VersionBump patch` reads the data
  file version, increments it, writes back to the data file copy, and uses the incremented version
  for the package. Source repo data file must be updated manually to match after copying the package.

- **CopilotActivity connector is GA (not preview)**: Trinity verified connectorId=MicrosoftCopilot,
  availabilityStatus=1, isPreview=false in Azure-Sentinel master. Safe to include in
  requiredDataConnectors for MVP content.

- **Module C is non-ASIM, direct-KQL**: No ASIM promotion, no custom parser dependency. ASIM comment
  must be `// ASIM: N/A — CopilotActivity direct-KQL, non-ASIM; no _Im* parser applicable` to pass
  Check 7. Do not claim custom parsers as ASIM equivalents.

- **AIGS-PA002 was mis-assigned module C**: It is an Azure OpenAI content-filter posture rule, naturally
  belonging to module A. Reassigned in guids.json _roadmap (GUID/path preserved).


---

## Session: 2026-07-23 — Module E Implementation (AIGS-AM001 Unauthorized Model Deployment)

**Objective:** Author AIGS-AM001 analytic rule, fix hunt comment, add Module E workbook surfaces.
Per controlling contracts: morpheus-module-e-design-gate, trinity-module-e-telemetry-contract v2,
morpheus-module-e-contract-acceptance (FINAL AUTHORITY), switch-module-e-validation-gates.

### What Was Built

1. **`AIGS-AM001-UnauthorizedModelDeployment.yaml`** (GUID `752bbac1-66ff-4bba-93f7-46a57bbd793d`):
   Fail-closed scheduled analytic rule. Detects successful CognitiveServices deployment writes
   absent from AIGS_ApprovedModels Active baseline. Pattern: materialize watchlist → toscalar
   gate `ActiveBaselineCount > 0` → leftouter join on composite
   `strcat(tolower(AccountName),"/",tolower(DeploymentName))` → `not(IsApproved)` where gate.
   Deduplication: `arg_max(TimeGenerated,*)` by ObservedKey before join. Terminal-status filter:
   `ActivityStatusValue in~ ("Success","Succeeded")`. `isnotempty(DeploymentName)` guard for
   account-level writes. queryFrequency: 1h, queryPeriod: 4h. Severity/Confidence: High/High.
   tactics: [] (MITRE omitted — governance finding). Response: PB-NOTIFY-01 only.
   Entity mappings: Account (Caller/FullName), IP (CallerIpAddress/Address),
   AzureResource (_ResourceId/ResourceId). ASIM: imAuditEvent native (no custom parser).

2. **`AIGS-Hunt-AIModelDeploymentChanges.yaml`** (comment-only F10 fix):
   Fixed misleading "ModelId (searchKey)" comment. Now clearly states:
   - `ItemKey` = Sentinel search-index column (not the join key)
   - Detection join key = data columns `DeploymentName` (hunt) or composite `AccountName/DeploymentName` (AM001 rule)
   Watchlist schema comment updated to lead with ItemKey.
   No KQL logic change; leftouter + WatchlistDeployed surface-all-when-absent behavior preserved.

3. **`AIGovernanceSolution.json`** (workbook):
   - Module E maturity `GA` → `Preview` in exec-coverage, modules-inventory, health-modules datatables
   - soc-modE-header: changed from warning style to success; updated text to distinguish packaged hunt
     (left-outer, seeding) from new scheduled rule (fail-closed, 1h/4h)
   - soc-hunt-deployments: removed "not authored" stale comment; added `in~` terminal-status filter;
     added isnotempty guard; clarifies hunt is distinct from AM001 scheduled rule
   - Replaced soc-am001 tile (broken KQL using `has`, `ActivityStatus`, `Resource`) with:
     (a) `soc-am001-alerts`: SecurityAlert history tile for AM001 alerts
     (b) `soc-am001`: Fail-closed workbook view mirroring AM001 rule logic exactly
   - compliance-mcsb: AIGS-AM001 evidence status updated for both AM-2 and AM-4 rows
   - compliance-nist: AIGS-AM001 evidence status updated for GOVERN 4.1
   - modules-inventory Module E: RuleCount 0→1, Maturity GA→Preview, ControlIDs updated,
     BatchStatus updated to reflect AM001 deployed
   - Module Coverage tab: Added Module E header, AIGS_ApprovedModels baseline inventory tile,
     recent deployment inventory tile (3 new items after modules-copilot-drift)

### Validation Results

- **Production validator (Test-AIGovernanceSource.ps1):** 15 checks, 114 passes, 0 warnings, 1 failure
  - FAIL (Check 13): guids.json roadmap entry — EXPECTED Tank action (promote AM001 from
    `_roadmap.analyticRules` to `analyticRules`, status `resolved`). Not Neo-owned.
  - Check 15 (Module E): All E7a–E7e sub-checks PASS for AIGS-AM001 and all AzureActivity files.
- **Module E regression (Test-ModuleEChecks.ps1):** Pre-existing runtime failure in Switch-owned
  DO NOT EDIT script. Unrelated to Neo content — parser succeeds, runtime fails on unicode `→`
  in Assert-Contains labels in this environment. Switch must resolve.

### Key Learnings

- **Workbook edit tool JSON string caveat:** The `edit` tool's old_str ending mid-way through a
  JSON string value (all on one line) causes the continuation to be left dangling. Always match
  COMPLETE structural units — never split a one-line JSON string value across old_str and what
  follows. Fix: PowerShell raw-string `Replace()` to repair orphaned JSON fragments.

- **Fail-closed pattern for "absence detection":** The module E rule uses a different fail-closed
  pattern from modules A/B/C. Rather than `kind=inner` (which would show nothing when baseline has
  approved entries), AM001 uses `leftouter` + guarded absence to DETECT what's NOT in the baseline.
  The guard (`ActiveBaselineCount > 0`) is essential to prevent fail-open when baseline is empty.
  The skill SKILL.md's "Required Pattern: inner join" covers the presence case; for absence detection,
  the guarded leftouter + not(IsApproved) pattern is the correct analogous pattern.

- **Deduplication before join:** Adding `summarize arg_max(TimeGenerated,*) by ObservedKey` BEFORE
  the leftouter join keeps one finding per composite account/deployment per evaluation window.
  This prevents alert storms for repeated successful writes of the same deployment.

- **`leftanti` in comments is safe:** Check 15 E7c-i strips comments before checking; `leftanti`
  in a prohibition comment does not trigger the check. Confirmed by validator passing Check 15.

- **guids.json / manifest are Tank gates:** Creating the rule file causes Check 13 to fail until
  Tank promotes the guids.json entry. This is expected and documented. Do not promote guids.json
  as Neo — it's explicitly Tank-owned.

### Decision Filed
`.squad/decisions/inbox/neo-module-e-content-implementation.md`
