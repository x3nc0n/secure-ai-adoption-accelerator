# Microsoft Sentinel — AI Governance Solution

> **Community Solution** · **v3.0.6-preview.1** · Module E Preview Batch
> Supported via [GitHub Issues](../../issues) · Published by [x3nc0n](https://github.com/x3nc0n)

---

## What This Is

**Microsoft Sentinel — AI Governance Solution** is a community-built, modular Microsoft Sentinel solution that detects AI governance violations across Microsoft AI and security services. It provides analytic rules, hunting queries, watchlists, workbook dashboards, and response playbooks so security teams can monitor, triage, and respond to AI configuration drift, unauthorized model deployments, and risky AI usage.

This solution follows all Microsoft Sentinel content and packaging conventions and is structured for a potential future upstream contribution to the [Azure/Azure-Sentinel](https://github.com/Azure/Azure-Sentinel) community repository. It is not a Microsoft-published product and carries no Microsoft support obligation.

---

## Current Status — Module E Preview Batch (v3.0.6-preview.1)

| Aspect | Status |
|--------|--------|
| Module A — Azure OpenAI / Foundry | ✅ Reference implementation |
| Module B — Agent 365 | ✅ Preview vertical slice: 2 rules, 1 hunt, 1 Watchlist, workbook coverage |
| Module C — M365 Copilot | ✅ Preview vertical slice: 1 rule (model drift), 1 hunt, 1 Watchlist, workbook coverage |
| Module E — Azure General | ✅ Preview vertical slice: 1 rule (unauthorized deployment), 1 hunt, 1 Watchlist, workbook coverage |
| Modules D, F, G | 🔵 Designed and contracted; scaffolding not yet complete |
| Solution package (`Package/`) | ✅ Generated with official V3 tooling; not hand-authored |
| Deploy to Azure button | ⏳ Pending package generation and remote URL |
| Validation workspace testing | 🔵 Gate 1b in progress (validation workspace: West US 2) |
| Content Hub / Marketplace publication | ⏸️ Blocked — gated for human approval |

This release contains deployable vertical slices for Module A (Azure OpenAI / Foundry),
Module B (Agent 365 Preview), Module C (M365 Copilot observed-state model drift), and Module E (Azure General unauthorized deployment detection). Modules D, F–G remain designed but are not yet deployable.

---

## Customer Outcomes

When fully deployed, this solution enables security teams to:

| Outcome | Governance Domain | Key Signals |
|---------|------------------|------------|
| Detect when AI content filter policies are removed or weakened | Configuration Drift | ARM events in `AzureActivity` (`raiPolicies/write`) |
| Detect approved active agents with no declared guardrails | Posture Assessment | `AgentsInfo` snapshot baseline comparison |
| Surface shadow AI applications and app governance violations | Posture Assessment | `CloudAppEvents` behavioral heuristics |
| Detect unauthorized AI model deployments | Audit Monitoring | `AzureActivity` (`deployments/write`), validated against approved baseline |
| Detect M365 Copilot agent model drift from approved binding | Configuration Drift | `CopilotActivity` observed AI model name/version vs. baseline |
| Identify Purview AI Hub policy violations | Audit Monitoring | `OfficeActivity` (OfficeWorkload == "Purview") |
| Flag anomalous Security Copilot session patterns | Risky Usage | `CopilotActivity` (Workload == "SecurityCopilot") |
| Notify SOC teams via Teams adaptive cards | Incident Response | AIGS-Notify-001-TeamsAlert playbook |
| Automatically restore diagnostic logging (approval-gated) | Incident Response | AIGS-Auto-001-RestoreDiagnostics playbook |

**Roadmap (verification pending):**
- Alert on unauthorized Copilot plugin settings changes (plugin lifecycle detection — `Operation` column not yet verified in published `CopilotActivity` schema)

All findings reference their governance control ID (`AIGS-<Domain><NNN>`), baseline authority (watchlist or threshold), and evaluation source. Coverage gaps surface as **Not Configured** — a missing connector or license is never reported as compliant.

---

## Module Matrix

| Module | Domain | Primary Table | Connector | ASIM | Status |
|--------|--------|--------------|-----------|------|--------|
| **A — Azure OpenAI / Foundry** | Config Drift, Audit | `AzureActivity` | Built-in (no connector required) | ✅ Native `imAuditEvent` | ✅ Reference implementation |
| **B — Agent 365** | Posture Assessment, Config Drift | `AgentsInfo` ⚠️ Preview | Microsoft Defender XDR | N/A (inventory table) | ✅ Preview implementation |
| **C — M365 Copilot** | Config Drift | `CopilotActivity` ⚠️ Preview | Microsoft Copilot (`MicrosoftCopilot`) GA | N/A — Direct-KQL (no parser) | ✅ Preview implementation |
| **D — Defender XDR** | Posture Assessment | `CloudAppEvents` | Microsoft Defender XDR + Defender for Cloud Apps | N/A | 🔵 Designed |
| **E — Azure General** | Audit Monitoring | `AzureActivity` | Built-in | ✅ Native `imAuditEvent` | ✅ Preview implementation |
| **F — Microsoft Purview** | Audit Monitoring | `OfficeActivity` | Office 365 connector | Partial `imAuditEvent` | 🔵 Designed |
| **G — Security Copilot** | Risky Usage | `CopilotActivity` ⚠️ Preview | Microsoft Copilot (`MicrosoftCopilot`) GA | N/A — Direct-KQL (no parser) | 🔵 Designed · Disabled by default |

### Notes

- **Module G is disabled by default** (`enableSecurityCopilotModule = false`). It requires a separately gated delegated-OAuth exception, Security Copilot SCU provisioning, and explicit administrator opt-in. Core solution functionality (Modules A–F) operates entirely via User-Assigned Managed Identity (UAMI) and does not depend on Module G.
- **Preview dependencies** (marked ⚠️): `AgentsInfo` and `CopilotActivity` are in public preview. Schema may change. `AgentsInfo` availability through standalone Sentinel streaming is not explicitly documented; unified Microsoft Defender portal access is recommended. See [PREREQUISITES.md](Solutions/Microsoft%20Sentinel%20-%20AI%20Governance%20Solution/PREREQUISITES.md).
- **Module A, C and E** are configured as follows: Module A and E use the native `AzureActivity` table; Module C uses direct-KQL queries against `CopilotActivity` without a custom parser.
- **Module A and E** are the only modules whose primary table (`AzureActivity`) is available in all Microsoft Sentinel workspaces without additional connector configuration.

---

## ASIM — Advanced Security Information Model

This solution promotes ASIM usage where official schemas exist:

| Table | ASIM Status | Function | Usage |
|-------|------------|---------|-------|
| `AzureActivity` | **Native ASIM** | `imAuditEvent` / `_Im_AuditEvent` | Modules A and E (ARM management-plane events) |
| `SigninLogs` / `AADNonInteractiveUserSignInLogs` | **Native ASIM** | `imAuthentication` / `_Im_Authentication` | Cross-module identity correlation enrichment |
| `CopilotActivity` | **No ASIM** (Preview table) | Direct-KQL (no parser) | Module C and G (direct KQL, solution-specific queries) |
| `AgentsInfo` | **No ASIM** | N/A — Defender XDR inventory | Module B |
| `CloudAppEvents` | **No ASIM** | N/A | Module D |
| `OfficeActivity` | **Partial ASIM** | `imAuditEvent` for applicable operations | Module F |

> **Note on custom parsers:** The solution does not ship custom ASIM parsers. The solution includes custom KQL queries against native tables (`CopilotActivity` direct-KQL for Modules C and G). These are labeled `AIGS_*` to prevent confusion with official ASIM functions.

---

## Solution Contents

The full roadmap includes:

| Category | Contents |
|----------|---------|
| Analytic Rules | 8 rules across 7 modules (Module A has 2: AIGS-CD001 + AIGS-AM001; Module B has 2: AIGS-PA001 + AIGS-CD002; Module C has 1: AIGS-CD003; Module E has 1: AIGS-AM001) |
| Hunting Queries | 7 queries (one per module) |
| Parsers | Custom KQL queries (no ASIM-normalized parsers shipped; direct-KQL for Module C/G `CopilotActivity`) |
| Workbooks | 1 workbook with 5 persona tabs (Executive, SOC Ops, Platform Health, Compliance Mapping, Module Coverage) |
| Watchlists | 7 watchlist pairs (CSV + JSON metadata) |
| Playbooks | 3 playbooks (AIGS-Notify-001-TeamsAlert, AIGS-Auto-001-RestoreDiagnostics, AIGS-Enrich-001-SecurityCopilot) |
| Solution Metadata | SolutionMetadata.json, Package/ (generated), api-versions.md, guids.json |

---

## Deployment

### Prerequisites

Before deploying, review [PREREQUISITES.md](Solutions/Microsoft%20Sentinel%20-%20AI%20Governance%20Solution/PREREQUISITES.md) for the full per-module connector, license, and RBAC requirements. At minimum:

- Microsoft Sentinel workspace (any SKU)
- Azure subscription with `User Access Administrator` rights (to assign UAMI roles)
- A user-assigned managed identity (UAMI) or the bootstrap script will create one
- Microsoft Teams OAuth connection configured for playbooks (see PREREQUISITES.md §UAMI and Identity)

> **Coverage gap reporting:** If a required connector is not installed or a license is unavailable, the workbook surfaces a **Not Configured** or **License Required** status tile. Rules for that module deploy in a disabled state. Installing the connector and re-enabling the rules does not require redeploying the full solution.

### Deploy to Azure

> ⏳ **Pending:** The Deploy to Azure button requires a publicly accessible template URL. This URL will be available after the solution package is generated and a repository release is published.
>
> Until then, deploy using the ARM templates directly from the `Solutions/Microsoft Sentinel - AI Governance Solution/` directory, or run the bootstrap script (documentation forthcoming).

<!-- DEPLOY-TO-AZURE-BUTTON-PENDING: Insert button once package URL is published -->

### Deployment Parameters

| Parameter | Type | Default | Required | Notes |
|-----------|------|---------|----------|-------|
| `workspaceResourceId` | string | — | ✅ Yes | Full ARM resource ID of the target Sentinel workspace |
| `location` | string | `eastus` | ✅ Yes | Must pass service-availability preflight |
| `tagEnvironment` | string | — | ✅ Yes | `Validation` or `Production` — no default; forces conscious selection |
| `notificationTeamsChannelId` | string | — | Yes (if notify enabled) | Teams channel for SOC notifications |
| `approverGroupObjectId` | string | — | Yes (if auto-remediation enabled) | Entra group whose members can approve remediation |
| `emailFallbackRecipients` | string | — | No | Semicolon-separated email list for approval timeout escalation |
| `metadataRetentionDays` | int | `90` | No | Retention for governance metadata |
| `contentRetentionDays` | int | `30` | No | Retention for optional prompt/response content |
| `enableContentIngestion` | bool | `false` | No | Prompt/response content ingestion (off by default; see PREREQUISITES.md) |
| `enableSecurityCopilotModule` | bool | `false` | No | Module G (requires delegated OAuth + SCU — see PREREQUISITES.md) |
| `enablePreviewModules` | bool | `true` | No | Modules B, C (preview connectors) |
| `uamiResourceId` | string | — | No | Bootstrap script creates one if blank |

---

## Response Policy

**Notify by default. Approve before writing.** Every remediation playbook:

- Declares its risk level, preconditions, approver identity, timeout behavior, rollback procedure, and failure handling
- Requires explicit human approval before any configuration write (approval timeout: 4 hours; no auto-approve on timeout)
- Writes all outcomes as Sentinel incident comments (durable audit trail)
- Supports opt-in per-control automation (disabled unless validation proves configuration safety)

See individual playbook documentation in [Playbooks/](Solutions/Microsoft%20Sentinel%20-%20AI%20Governance%20Solution/Playbooks/).

---

## Governance Framework Mappings

Controls map many-to-many to:
- **Microsoft Cloud Security Benchmark (MCSB)** — primary mapping
- **NIST AI Risk Management Framework (AI RMF)** — primary mapping
- ISO/IEC 42001, EU AI Act — available in workbook Compliance Mapping tab (extensible)

---

## Support and Contributing

This is a **Community** solution. Support is provided on a best-effort basis through [GitHub Issues](../../issues).

- Report bugs, request features, or ask questions via GitHub Issues
- Pull requests welcome — see contributing guidelines (forthcoming)
- For upstream Microsoft Sentinel contribution status, see [gated decisions](../../issues) (blocked pending human approval)

**This solution is not affiliated with, endorsed by, or supported by Microsoft Corporation.** Publisher: [x3nc0n](https://github.com/x3nc0n).

---

## Release History

See [CHANGELOG.md](Solutions/Microsoft%20Sentinel%20-%20AI%20Governance%20Solution/CHANGELOG.md) and [ReleaseNotes.md](Solutions/Microsoft%20Sentinel%20-%20AI%20Governance%20Solution/ReleaseNotes.md).

Current release: **v3.0.6-preview.1** — Module E Preview Batch (CognitiveServices unauthorized deployment detection; fail-closed baseline matching).
