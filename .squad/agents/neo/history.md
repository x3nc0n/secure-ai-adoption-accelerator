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
