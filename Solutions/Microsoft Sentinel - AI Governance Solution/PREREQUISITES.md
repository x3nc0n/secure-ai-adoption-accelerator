# PREREQUISITES — Microsoft Sentinel – AI Governance Solution

**Solution version:** v3.0.1-preview.1
**Last updated:** 2026-07-17

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

**Status:** 🔵 Designed
**Modules deployed by default:** Enabled when `enablePreviewModules = true` (requires connector)

### Data Source

| Item | Details |
|------|---------|
| **Connector** | Microsoft Copilot Data Connector ⚠️ **Preview** (Content Hub) |
| **Table** | `CopilotActivity` ⚠️ **Preview** |
| **ASIM** | Custom: `AIGS_CopilotActivity_Normalized` (not ASIM; solution-specific normalization) |
| **Verification query** | `CopilotActivity \| where Workload has "MicrosoftCopilot" \| take 1` |

### License Requirements

| Requirement | Notes |
|-------------|-------|
| Microsoft 365 Copilot license | Required for Copilot plugin activity to appear |
| Microsoft Purview audit logging enabled | `CopilotActivity` is sourced from Purview UAL |

### Watchlists Used

| Watchlist | Purpose | Key Column |
|-----------|---------|-----------|
| `AIGS_ApprovedCopilotPlugins` | Approved Copilot plugin names and approved states | `ItemKey` = plugin name |
| `AIGS_M365CopilotBaseline` | M365 Copilot configuration baseline | `ItemKey` = configuration key |

### Analytic Rules

| Rule ID | Name | Table | Severity | Confidence |
|---------|------|-------|----------|-----------|
| `AIGS-CD003` | Unauthorized Copilot Plugin Added Outside Approved List | `CopilotActivity` | High | High (deterministic watchlist comparison) |

### Known Limitations

- `CopilotActivity` and the Microsoft Copilot Data Connector are in public preview. Table schema and RecordType values may change.
- `CloudAppEvents` is **not** the authoritative table for plugin management events — it lacks confirmed ActionType values for plugin lifecycle operations. Do not use `CloudAppEvents` as the primary source for this module.

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
