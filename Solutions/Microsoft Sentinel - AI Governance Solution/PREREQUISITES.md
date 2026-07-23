# PREREQUISITES — Microsoft Sentinel – AI Governance Solution

**Solution version:** v3.0.5-preview.1
**Last updated:** 2026-07-23

---

## Overview

This document describes all prerequisites for deploying and operating **Microsoft Sentinel — AI Governance Solution**. Prerequisites are organized by module. Install only the connectors for the modules you intend to enable. Modules with unmet prerequisites deploy in a disabled or degraded state and surface their status in the workbook — a coverage gap is never reported as compliant.

---

## Global Prerequisites

These requirements apply to all modules.

### Microsoft Sentinel Workspace

| Requirement | Details |
|-------------|---------|
| Microsoft Sentinel workspace | Any region; any Log Analytics SKU |
| Microsoft Sentinel solution installed | Sentinel must be enabled on the workspace |
| Workspace resource ID | Required deployment parameter (`workspaceResourceId`) |

### Azure RBAC (Deployment)

| Role | Scope | Purpose |
|------|-------|---------|
| `Microsoft Sentinel Contributor` | Sentinel workspace | Deploy analytic rules, workbooks, playbooks, watchlists |
| `Logic App Contributor` | Subscription or resource group | Deploy Logic App (playbook) resources |
| `User Access Administrator` | Subscription or resource group | Assign RBAC roles to UAMI |
| `Managed Identity Contributor` | Subscription or resource group | Create UAMI (or provide existing UAMI resource ID) |

> **Bootstrap script:** If you do not have a pre-existing UAMI, the bootstrap script (documentation forthcoming) creates one and assigns the required roles. Provide the resulting `uamiResourceId` as a deployment parameter.

---

## UAMI and Identity Requirements

### User-Assigned Managed Identity (UAMI)

All playbooks except AIGS-Enrich-001-SecurityCopilot use a User-Assigned Managed Identity (UAMI). This is an architectural requirement — system-assigned identities are not used. You may provide a single UAMI or separate UAMIs per playbook; permission sets must not be broadened merely for consolidation convenience.

| Playbook | Required UAMI Roles | Scope |
|----------|---------------------|-------|
| **AIGS-Notify-001-TeamsAlert** | `Microsoft Sentinel Reader` (`ab8e14d6-4a74-4a29-9ba8-549422addade`) | Sentinel workspace resource ID |
| **AIGS-Auto-001-RestoreDiagnostics** | `Monitoring Contributor` + `Microsoft Sentinel Responder` | Target resource group (Monitoring Contributor); Sentinel workspace (Responder) |

### Microsoft Teams OAuth Connection

AIGS-Notify-001-TeamsAlert and AIGS-Auto-001-RestoreDiagnostics use the **Microsoft Teams connector** with an OAuth connection. This is a delegated or service account connection — **not** an incoming webhook URL.

- Webhooks are supported only for simple text notifications and cannot process adaptive card approval actions.
- The approval capability in AIGS-Auto-001-RestoreDiagnostics (bi-directional adaptive card) requires the Teams connector's **"Post adaptive card and wait for a response"** action, which requires an OAuth connection.
- Configure the Teams OAuth connection at deployment time. A service account with a Teams license is recommended for production deployments.

**Deployment parameters:**

| Parameter | Purpose |
|-----------|---------|
| `notificationTeamsChannelId` | Teams channel ID where SOC notifications are posted |
| `approverGroupObjectId` | Entra group object ID — members can approve remediation requests |
| `emailFallbackRecipients` | Fallback email list used when Teams approval times out (4-hour default) |

### Security Copilot — Delegated OAuth Exception

> ⚠️ **Exception to UAMI policy**

AIGS-Enrich-001-SecurityCopilot (Module G optional enrichment playbook) uses **delegated OAuth** because the Security Copilot API does not currently support managed identity authentication. This is a documented architectural exception, not a design choice.

- Requires separate administrator consent for the OAuth credential
- SCU capacity must be provisioned before this playbook is activated (cost-bearing — gated decision)
- Module G is **disabled by default** (`enableSecurityCopilotModule = false`)
- Core solution functionality (Modules A–F) is entirely unaffected when Module G is disabled
- Disabling Module G removes the delegated OAuth requirement entirely

---

## Retention and Content Ingestion

| Parameter | Default | Notes |
|-----------|---------|-------|
| `metadataRetentionDays` | `90` | Applies to governance metadata (rule findings, watchlist data, incident comments) |
| `contentRetentionDays` | `30` | Applies to optional prompt/response content ingestion |
| `enableContentIngestion` | `false` | **Off by default.** Prompt and response content may contain organizational intellectual property. Enable only after completing consent, legal, and privacy review. |

**Content ingestion advisory:** When enabled, prompt and response content may include personal data, regulated data, trade secrets, and third-party copyrighted material. Consult your privacy and legal team before enabling. The solution provides masking/redaction options and requires explicit cost disclosure review before activation.

---

## Module A — Azure OpenAI / Foundry

**Status:** ✅ Reference implementation
**Modules deployed by default:** Enabled

### Data Source

| Item | Details |
|------|---------|
| **Connector** | Azure Activity Logs — built-in; no connector installation required |
| **Table** | `AzureActivity` |
| **ASIM** | `imAuditEvent` / `_Im_AuditEvent` (native ASIM — no custom parser) |
| **Operations detected** | `Microsoft.CognitiveServices/accounts/raiPolicies/write` (content filter policy change) · `Microsoft.CognitiveServices/accounts/deployments/write` (model deployment) |
| **Verification query** | `AzureActivity \| where OperationNameValue has "COGNITIVESERVICES" \| take 1` |

### License Requirements

| Requirement | Notes |
|-------------|-------|
| Azure subscription with Azure OpenAI or Azure AI Foundry resources | Required for telemetry to exist; `AzureActivity` itself requires no additional license |
| Microsoft Sentinel (any SKU) | For rule deployment |

### Watchlists Used

| Watchlist | Purpose | Key Column |
|-----------|---------|-----------|
| `AIGS_ContentFilterPolicies` | Approved content filter policy names and severity thresholds | `ItemKey` = policy name |
| `AIGS_ApprovedModels` | Approved model deployment names and resource tags | `ItemKey` = model deployment name |

### Analytic Rules

| Rule ID | Name | Table | Severity | Confidence |
|---------|------|-------|----------|-----------|
| `AIGS-CD001` | Content Filter Policy Removed or Weakened | `AzureActivity` | High | High (deterministic) |
| `AIGS-AM001` | Unauthorized AI Model Deployment Detected | `AzureActivity` | High | High (deterministic) |

### Playbooks

| Playbook | Trigger |
|----------|---------|
| AIGS-Notify-001-TeamsAlert | Fires on any AIGS rule incident |
| AIGS-Auto-001-RestoreDiagnostics | Fires on incidents with `AIGS-CD` control IDs (approval-gated) |

### Known Limitations

- Content filter policy changes appear only on ARM management-plane events. Data-plane inference API calls appear in `AzureDiagnostics` — this module does not analyze inference traffic.
- Azure Policy compliance events for Cognitive Services are not currently ingested; ARM events are the sole detection mechanism.

---

## Module B — Agent 365

**Status:** ✅ Preview implementation
**Modules deployed by default:** Enabled when `enablePreviewModules = true` (requires connector)

### Data Source

| Item | Details |
|------|---------|
| **Connector** | Microsoft Defender XDR (`MicrosoftDefenderAdvancedThreatProtection`) |
| **Table** | `AgentsInfo` ⚠️ **Preview** (supersedes deprecated `AIAgentsInfo` — do not use `AIAgentsInfo`) |
| **ASIM** | N/A — Defender XDR proprietary inventory table; no ASIM schema |
| **Table semantics** | **Snapshot** — records current configuration state, not an event stream. Analytic rules must be scheduled (every 4 hours recommended), not near-real-time |
| **Verification query** | `AgentsInfo \| take 1` |

### License Requirements

| Requirement | Notes |
|-------------|-------|
| Microsoft Defender for Endpoint Plan 2 or Microsoft 365 E5 Security | Required for Defender XDR connector and `AgentsInfo` table |
| Agent 365 licensing | Required for agent data to populate `AgentsInfo` |

### Watchlists Used

| Watchlist | Purpose | Key Column |
|-----------|---------|-----------|
| `AIGS_ApprovedAgents` | Approved AgentId, expected Platform and Version, and guardrail classification context | `ItemKey` (detection join uses `AgentId`) |

### Analytic Rules

| Rule ID | Name | Table | Severity | Confidence |
|---------|------|-------|----------|-----------|
| `AIGS-PA001` | Active Published Agent Missing Declared Guardrails | `AgentsInfo` | High | High (empty documented field + fail-closed baseline) |
| `AIGS-CD002` | Agent Version or Platform Drift | `AgentsInfo` | Medium | High (deterministic baseline mismatch) |

### Hunting Query

`AIGS-Hunt-AgentConfigurationDrift` surfaces active agents absent from the approved baseline and
agents whose documented `Version` or `Platform` differs. If the Watchlist has no Active rows, the
hunt returns active inventory for baseline seeding; it does not claim compliance.

### Known Limitations

- `AgentsInfo` is a Preview table; schema may change between Defender XDR releases.
- Snapshot semantics mean there is inherent latency between an agent configuration change and detection. Near-real-time detection is not supported for this module.
- `Guardrails` is documented as dynamic, but its internal object schema is not published. AIGS-PA001 only evaluates empty, null, `[]`, and `{}` values and does not inspect undocumented subfields.
- `Guardrails` does not prove whether an external Microsoft Purview DLP policy is applied or enforced. Purview enforcement belongs to Module F.
- `AgentsInfo` is not listed among the Defender XDR connector's selectable streaming tables. Unified Microsoft Defender portal access is the recommended execution path until standalone Sentinel availability is explicitly documented.
- The current schema has no stable creator UPN or external-tenant field, so the planned "agents registered by external identity" hunt was rejected rather than implemented with invented fields.

---

## Module C — M365 Copilot

**Status:** ✅ Preview implementation  
**Modules deployed by default:** Enabled when `enablePreviewModules = true` (requires connector)

### Detection Scope — Observed-State Model Binding Drift

Module C detects **observed-state, expected-state model binding drift**: it compares the AI model
name and version observed in `CopilotActivity` events for each Copilot agent against the approved
binding recorded in the `AIGS_M365CopilotBaseline` watchlist. A finding is produced only when the
observed model or version differs from the approved value for a baselined agent.

This is **not** plugin settings drift, plugin lifecycle detection, or content-based analysis.
Module C uses direct-KQL against `CopilotActivity` with no ASIM normalization parser and no
custom parser dependency. Lifecycle operations (plugin create/update/delete/enable/disable,
promptbook, tenant settings) are **not** detected in this pass — they depend on the `Operation`
column, which is not in the published `CopilotActivity` table schema and cannot be safely
referenced in scheduled analytic content.

### Data Source

| Item | Details |
|------|---------|
| **Connector** | Microsoft Copilot (`MicrosoftCopilot`) — **GA** (Content Hub) |
| **Table** | `CopilotActivity` |
| **ASIM** | N/A — direct-KQL; no `_Im*` ASIM parser applicable to `CopilotActivity` |
| **Verified schema** | 24 documented columns per Microsoft Learn (updated 2026-05-06) |
| **Verification query** | `CopilotActivity \| take 1` |

### License Requirements

| Requirement | Notes |
|-------------|-------|
| Microsoft 365 Copilot license | Required for CopilotActivity events to be generated |
| Microsoft Purview audit logging enabled | `CopilotActivity` is sourced from Purview UAL (15–60 min ingest lag) |
| Microsoft Sentinel workspace | Any SKU |

### Watchlists Used

| Watchlist | Purpose | Detection Join Key |
|-----------|---------|-----------|
| `AIGS_M365CopilotBaseline` | Approved Copilot agent → AI model binding baseline | `AgentId` (detection join; `ItemKey` is the search index) |

### Analytic Rules

| Rule ID | Name | Table | Severity | Confidence |
|---------|------|-------|----------|-----------|
| `AIGS-CD003` | M365 Copilot Agent Model Drift from Baseline | `CopilotActivity` | Medium | High (deterministic inner-join; fail-closed) |

`AIGS-CD003` runs every 1 hour, looks back 2 hours (accounts for Purview UAL ingest lag), and
selects the latest observed state per `AgentId` via `arg_max(TimeGenerated, *)`. An absent,
empty, or template-only `AIGS_M365CopilotBaseline` produces zero results. A blank
`ExpectedModelName` or `ExpectedModelVersion` in a baseline row disables comparison for that
property only.

### Hunting Query

`AIGS-Hunt-CopilotAgentModelInventory` surfaces all observed Copilot agents, their distinct AI
model names, versions, and host applications over the selected time range. Use this inventory
as the basis for populating `AIGS_M365CopilotBaseline` before enabling drift detection.

### Baseline Workflow

1. Run `AIGS-Hunt-CopilotAgentModelInventory` to discover observed agent/model bindings.
2. For each agent to govern, add a row to `AIGS_M365CopilotBaseline` with `Status=Active`,
   the approved `ExpectedModelName` and `ExpectedModelVersion`, and a `BaselineOwner`.
3. Leave `ExpectedModelName` or `ExpectedModelVersion` blank to skip comparison for that
   property for a given agent.
4. `AIGS-CD003` will begin producing findings on the next scheduled run.

### Known Limitations

- **No lifecycle operation detection this pass.** The `Operation` column is documented separately in Purview audit-log-activities but is not listed in the published `CopilotActivity` table schema. Plugin lifecycle, promptbook, and tenant settings operations cannot be safely referenced in scheduled analytic content until the column is confirmed as queryable. These scenarios remain roadmap-only.
- **Observed-state only.** `CopilotActivity` records what model was observed per interaction event, not configuration changes or admin actions. Model drift is inferred from observed behavior, not from an authoritative config-change event.
- **UAL ingest lag.** Purview UAL-sourced events have a 15–60 minute ingest delay. The 1h/2h frequency/lookback window accounts for this lag.
- **`LLMEventData` contents not documented.** The `LLMEventData` dynamic column exists in the schema but its sub-fields are not published. No Module C content references `LLMEventData` sub-fields.
- **`AccessedResources` not in table schema.** This field is mentioned in Purview audit context documentation but is not listed in the `CopilotActivity` column list. It is never referenced in Module C content.

---

## Module D — Defender XDR

**Status:** 🔵 Designed
**Modules deployed by default:** Enabled (requires connector + Defender for Cloud Apps)

### Data Source

| Item | Details |
|------|---------|
| **Connector** | Microsoft Defender XDR + Microsoft Defender for Cloud Apps |
| **Table** | `CloudAppEvents` |
| **ASIM** | N/A — no applicable ASIM schema for app governance config events |
| **Verification query** | `CloudAppEvents \| take 1` |

### License Requirements

| Requirement | Notes |
|-------------|-------|
| Microsoft Defender for Cloud Apps | Required for `CloudAppEvents` to be populated |
| Microsoft Defender XDR connector | Must be configured in the workspace |

### Watchlists Used

| Watchlist | Purpose | Key Column |
|-----------|---------|-----------|
| `AIGS_DefenderXDRBaseline` | Approved AI applications and governance state | `ItemKey` = application name or ID |

### Analytic Rules

| Rule ID | Name | Table | Severity | Confidence |
|---------|------|-------|----------|-----------|
| `AIGS-PA002` | Unsanctioned AI Application Access Detected | `CloudAppEvents` | Medium | Medium (behavioral heuristic + watchlist comparison) |

### Known Limitations

- `CloudAppEvents` requires Defender for Cloud Apps to be deployed and connected — it is not a free ingestion path.
- Deterministic policy-drift detection against `CloudAppEvents` uses heuristic behavioral signals. Specific Defender XDR AI policy ActionType values are not yet confirmed in official documentation. Hunting queries are the preferred surface for this module until ActionType values are verified.

---

## Module E — Azure General

**Status:** 🔵 Designed
**Modules deployed by default:** Enabled (no additional connector required)

### Data Source

| Item | Details |
|------|---------|
| **Connector** | Azure Activity Logs — built-in |
| **Table** | `AzureActivity` |
| **ASIM** | `imAuditEvent` / `_Im_AuditEvent` (native ASIM) |
| **Verification query** | `AzureActivity \| take 1` |

### Watchlists Used

| Watchlist | Purpose | Key Column |
|-----------|---------|-----------|
| `AIGS_ApprovedModels` | Approved model deployment names and approved regions | `ItemKey` = model deployment name |

### Analytic Rules

| Rule ID | Name | Table | Severity | Confidence |
|---------|------|-------|----------|-----------|
| `AIGS-AM001` | Unauthorized AI Model Deployment Detected | `AzureActivity` | High | High (deterministic ARM event) |

> Note: AIGS-AM001 is shared with Module A in the detection scope. Module E includes the hunting query for AI resources provisioned outside approved regions.

---

## Module F — Microsoft Purview

**Status:** 🔵 Designed
**Modules deployed by default:** Enabled (requires Office 365 connector + Purview AI Hub activity)

### Data Source

| Item | Details |
|------|---------|
| **Connector** | Office 365 connector (`Office365`) |
| **Table** | `OfficeActivity` filtered: `OfficeWorkload == "Purview"` |
| **Important** | `PurviewAuditLogs` is **not** a real Microsoft Sentinel table name. Purview audit events route to `OfficeActivity`. **Do not use `PurviewAuditLogs` in any query.** |
| **ASIM** | Partial: `imAuditEvent` applies to some OfficeActivity operations; Purview-specific fields have no ASIM mapping |
| **Health-check query (mandatory)** | `OfficeActivity \| where OfficeWorkload == "Purview" \| summarize LastEvent = max(TimeGenerated) \| where LastEvent > ago(7d)` |
| **Verification query** | `OfficeActivity \| where OfficeWorkload == "Purview" \| take 1` |

### License Requirements

| Requirement | Notes |
|-------------|-------|
| Microsoft Purview AI Hub | Required for AI Hub policy events to appear in Office 365 audit log |
| Microsoft 365 with Office 365 connector | Required for `OfficeActivity` table |

### Watchlists Used

| Watchlist | Purpose | Key Column |
|-----------|---------|-----------|
| `AIGS_PurviewPolicies` | Approved Purview AI Hub policy names | `ItemKey` = policy name |

### Analytic Rules

| Rule ID | Name | Table | Severity | Confidence |
|---------|------|-------|----------|-----------|
| `AIGS-AM002` | Purview AI Hub Policy Violation Detected | `OfficeActivity` | High | Medium (UAL event match; exact Operation name must be verified in validation workspace before GA) |

### Known Limitations

- The exact `Operation` field values for Purview AI Hub policy violations are not yet confirmed in Microsoft's published audit-log-activities documentation. The rule must include a mandatory health-check KQL and will deploy in a **preview state** until Operation values are verified.
- The Office 365 connector must be installed and Purview AI Hub activity must be occurring for this module to yield data.

---

## Module G — Security Copilot (Optional · Disabled by Default)

**Status:** 🔵 Designed · Disabled by default
**Activation parameter:** `enableSecurityCopilotModule = true` (requires additional gated steps below)

> ⚠️ **This module is disabled by default.** Activating it requires explicit administrator opt-in, a separately gated delegated-OAuth exception, and SCU provisioning (cost-bearing). Core solution functionality (Modules A–F) does not depend on Module G.

### Activation Requirements

To activate Module G, all of the following must be completed:

1. **Administrator opt-in:** Set `enableSecurityCopilotModule = true` at deployment
2. **Delegated OAuth credential:** Configure an OAuth connection for the Security Copilot connector (managed identity is not supported by the Security Copilot API — this is a documented exception to the UAMI architectural policy)
3. **Separate administrator consent:** Security Copilot connector requires separate admin consent
4. **Security Copilot UAL logging enabled:** In Security Copilot Owner settings, enable "Logging audit data in Microsoft Purview" — the connector alone is insufficient
5. **SCU provisioning:** Security Copilot capacity units (SCUs) must be provisioned (cost-bearing — this is a gated decision requiring explicit human authorization)
6. **CopilotActivity table verified:** Run `CopilotActivity | where Workload has "SecurityCopilot" | take 1` to confirm data flow

### Data Source

| Item | Details |
|------|---------|
| **Connector** | Microsoft Copilot Data Connector ⚠️ **Preview** |
| **Table** | `CopilotActivity` — `Workload == "SecurityCopilot"` |
| **ASIM** | Custom: `AIGS_CopilotActivity_Normalized` (not ASIM) |
| **Verification query** | `CopilotActivity \| where Workload has "SecurityCopilot" \| take 1` |

### License Requirements

| Requirement | Notes |
|-------------|-------|
| Microsoft Security Copilot with SCU | **Cost-bearing.** SCU provisioning is a gated decision. Estimated cost: per-SCU consumption per enrichment call (consult Security Copilot pricing documentation for current rates) |
| Microsoft Purview audit logging | Required for CopilotActivity to receive Security Copilot events |

### Identity Exception

AIGS-Enrich-001-SecurityCopilot uses **delegated OAuth** (not UAMI). This is a documented architectural exception to the UAMI policy, justified by the Security Copilot API's current authentication requirements. Revocation and audit of the delegated credential are the responsibility of the deploying organization.

### Analytic Rules

| Rule ID | Name | Table | Severity | Confidence |
|---------|------|-------|----------|-----------|
| `AIGS-RU001` | Anomalous Security Copilot Session Volume or Unauthorized User | `CopilotActivity` | Medium | Medium (threshold-based behavioral anomaly) |

> Note: AIGS-RU001 deploys in a **disabled** state when `enableSecurityCopilotModule = false`. The `AIGS_CopilotActivity_Normalized` parser deploys regardless (zero cost) but is non-functional without the connector.

---

## Validation Semantics

> **No detection firing is required to validate this solution.**

Validation proves that solution artifacts deploy, load, wire dependencies, and can be removed cleanly. It does **not** require detections to produce results or incidents. Representative source telemetry is not expected in all validation environments.

| Validation Type | What Is Validated | Alert Firing Required? |
|----------------|------------------|----------------------|
| Gate 1a — CI | JSON/YAML syntax, GUID consistency, KQL syntax, secret scan, Watchlist schema, package generation | ❌ No |
| Gate 1b — Deployment | Artifacts deploy, workbook loads, rules appear in Analytics blade, playbooks deploy and show Enabled, clean removal, idempotent redeployment | ❌ No |
| Gate 3 — Full validation | All modules validate deployment mechanics; workbook tabs render (empty state acceptable); module health tiles show correct Not Configured status where connectors absent | ❌ No |

**KQL logic correctness** is validated by syntax parsing and, where feasible, fixture-based testing against known-good event samples. Any naturally occurring alert in the validation workspace is useful incidental evidence — it is not a release gate.
