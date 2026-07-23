# Squad Decisions

**Updated:** 2026-07-16T18:15:10.970-07:00  
**Status:** Discovery decisions consolidated, implementation planning ready  
**Merge Summary:** 18 interactive decisions + 20 architecture defaults (Morpheus, with Switch correction applied) + 7 gated/irreversible decisions = 45 approved decisions in active scope

## Active Decisions

### Interactive Walkthrough Decisions (x3nc0n, 2026-07-16T17:47:14.338-07:00)

The following decisions were reached in the interactive team walkthrough and define the core product strategy, governance scope, deployment model, and operational boundaries.

#### Decision: Distribution Target
- **Status:** Approved
- **Decision:** Build a private/internal deployable MVP first, while preserving a path to an upstream Azure-Sentinel contribution later.
- **Implications:** Optimize initial packaging, validation, and documentation for internal deployment; retain official solution structure and generated-package conventions so upstream hardening does not require restructuring.

#### Decision: Deployment Topology
- **Status:** Approved
- **Decision:** Validate the MVP in one reference tenant and Microsoft Sentinel workspace, parameterized for enterprise multi-workspace rollout.
- **Implications:** Do not hard-code tenant, subscription, resource group, workspace, identity, baseline, approver, or notification values. Multitenant MSSP orchestration is not an MVP requirement.

#### Decision: First-Release Platform Scope
- **Status:** Approved
- **Decision:** The first release will provide broad coverage across Microsoft 365, Defender XDR, Agent 365, Microsoft Foundry, Azure, Microsoft Purview, and Security Copilot.
- **Implications:** Design content as capability-based modules with explicit connector, license, telemetry, and maturity prerequisites. Unsupported or unavailable telemetry must be shown as a coverage gap rather than inferred as compliant.

#### Decision: Modular Solution Packaging
- **Status:** Approved
- **Decision:** Package broad first-release coverage as one modular Microsoft Sentinel solution with core content, optional platform modules, and coverage-health reporting.
- **Implications:** Platform-specific content declares its connectors, licensing, and telemetry prerequisites. Missing modules or data sources surface as Not Configured or Unsupported, never Compliant.

#### Decision: Baseline Authority (Desired-State Authority)
- **Status:** Approved
- **Decision:** Store approved AI governance baselines in Git, deploy query-optimized copies to Microsoft Sentinel Watchlists, and use Azure Policy as the evaluation authority where it supports the control.
- **Implications:** Baseline changes require version control and review. Watchlists are generated runtime state, not independently edited policy. Findings must identify baseline version and evaluation source.

#### Decision: Telemetry Acquisition and ASIM
- **Status:** Approved
- **Decision:** Include optional API and Resource Graph snapshot collectors where native telemetry is insufficient, but do not duplicate data available through Microsoft Sentinel ASIM.
- **Directive:** Explicitly identify and promote ASIM wherever analytic rules, hunting queries, parsers, or workbook queries use ASIM-normalized data.
- **Implications:** Apply telemetry precedence in this order: ASIM-normalized source, existing native table/connector, then optional custom collection. Each content item documents its data contract and ASIM parser dependency.

#### Decision: Validation Environment
- **Status:** Approved
- **Decision:** Create a dedicated reference tenant and Microsoft Sentinel workspace with representative Microsoft AI and security services seeded for validation.
- **Implications:** Use the environment to verify connectors, licenses, table schemas, API permissions, representative events, KQL fixtures, workbook behavior, package deployment, and playbook safety before release.

#### Decision: Response and Remediation Policy
- **Status:** Approved
- **Decision:** Notify by default, require human approval for configuration writes, and permit only narrowly guarded low-risk automatic remediation.
- **Implications:** Every remediation playbook declares risk, preconditions, approver, timeout behavior, rollback, audit trail, and failure handling. Automatic remediation is opt-in per control and disabled unless validation proves it preserves existing configuration.

#### Decision: Deployment and Playbook Identity (UAMI Model)
- **Status:** Approved with exception noted
- **Decision:** Support well-scoped, least-privilege user-assigned managed identities for deployment modules and all playbooks. Provide both a Deploy to Azure experience and a bootstrap script for UAMI creation and RBAC assignment.
- **Sub-Decision:** A single UAMI may be documented as an optional consolidation when playbook permission sets align, but it is not required and must not broaden permissions merely for convenience.
- **Exception:** The Security Copilot connector currently requires delegated OAuth and does not support UAMI; direct integration requires a separate explicit decision.
- **Implications:** Publish per-module permission matrices, prefer separate UAMIs when duties differ, and validate role-assignment scope during deployment.

#### Decision: Security Copilot Authentication Exception
- **Status:** Approved
- **Decision:** Offer Security Copilot enrichment as an optional module with an explicit delegated-OAuth exception and separate administrator consent.
- **Implications:** Core deployment and playbooks remain UAMI-based. The Security Copilot module clearly discloses delegated identity, SCU consumption, licensing, consent, revocation, and audit requirements and can be omitted without reducing core solution functionality.

#### Decision: Governance Framework Mapping
- **Status:** Approved
- **Decision:** Map first-release controls to the Microsoft Cloud Security Benchmark and NIST AI Risk Management Framework using an extensible mapping model.
- **Implications:** Control identifiers remain solution-owned and support many-to-many framework mappings. Workbook and documentation surfaces can add ISO/IEC 42001, EU AI Act, or organization-specific frameworks without changing detection logic.

#### Decision: Solution Name
- **Status:** Approved
- **Decision:** Name the product `Microsoft Sentinel - AI Governance Solution`.
- **Implications:** Use the name consistently for the solution manifest, package metadata, workbook title, documentation, control namespace, and internal deployment experience. Validate any required publishing-specific variation before an upstream submission.

#### Decision: Publisher and Support Owner
- **Status:** Approved
- **Decision:** Use `x3nc0n` as the initial publisher and support owner for `Microsoft Sentinel - AI Governance Solution`.
- **Implications:** Package metadata and documentation identify x3nc0n as publisher. Use the repository GitHub Issues page as the support channel once a remote repository URL is established; do not represent Microsoft as publisher without formal acceptance.

#### Decision: Notification and Approval Experience
- **Status:** Approved
- **Decision:** Use Teams adaptive cards as the primary notification and approval experience, write workflow outcomes to Microsoft Sentinel incident comments, and provide email fallback.
- **Implications:** Teams destination, approver group, timeout, escalation, and email recipients are deployment parameters. Incident comments are the durable response audit trail.

#### Decision: Platform Module Graduation Criteria
- **Status:** Approved
- **Decision:** Include a platform module in the first release only when it has validated telemetry, a coverage-health check, at least one analytic rule, at least one hunting query, workbook representation, and response guidance.
- **Implications:** Documentation-only placeholders do not count as platform coverage. Every module must declare prerequisites, sample evidence, validation status, and known blind spots.

#### Decision: Preview Capability Policy
- **Status:** Approved
- **Decision:** Include preview capabilities as optional modules that are enabled by default, while clearly labeling every preview dependency and allowing deployment-time disablement.
- **Implications:** Preview status appears in manifests, deployment UI, documentation, workbook health, and content metadata. Core GA functionality must remain operable when preview modules are disabled.

#### Decision: Retention and Support
- **Status:** Approved
- **Decision:** Propose configurable defaults of 90 days for governance metadata and 30 days for optional prompt and response content.
- **Sub-Decision:** Publish and support `Microsoft Sentinel - AI Governance Solution` as a Community solution.
- **Implications:** Deployment exposes retention parameters and estimates their cost impact. Solution metadata and documentation clearly identify the Community support tier and route support through the repository's GitHub Issues page.

#### Decision: AI Data Handling
- **Status:** Approved
- **Decision:** Use metadata-only ingestion by default. Provide prompt and response ingestion as an optional module that customers can enable or disable because the content may constitute organizational intellectual property and can be relevant to authorized governance teams.
- **Implications:** Content ingestion is off by default and requires explicit consent, least-privilege access, regional-boundary checks, configurable retention, masking/redaction options, auditability, cost disclosure, and documentation of personal, regulated, and third-party data risks.

---

### Morpheus Autonomous Resolution — Architecture Defaults (2026-07-16T18:07:00.000-07:00)

**Authority:** User confirmed all prior decisions in interactive walkthrough; instructed team to work autonomously and make good decisions on remaining items.

**Review Status:** Approved by Switch (validation engineer) with one correction applied.

**Principle:** Every default below is reversible, parameterized, and chosen to minimize lock-in.

#### 1. Primary Deployment Region
- **Default:** `eastus`
- **Rationale:** Broad service availability for Sentinel, Azure OpenAI, Logic Apps, and Entra. Highest density of AI governance-relevant services in GA.
- **Safeguard:** Deployment templates MUST include a service-availability preflight step that validates required resource providers and SKUs are available in the selected region before any resource creation. Region is always a deployment parameter — never hard-coded.

#### 2. Workbook Personas and Navigation
- **Default personas (tab-based navigation):**
  | Tab | Persona | Purpose |
  |-----|---------|---------|
  | Executive Summary | CISO / Security Director | Posture score, coverage gaps, trend lines, framework compliance heat map |
  | SOC Operations | SOC Analyst / Incident Responder | Active alerts, triage queue, recent drift events, response status |
  | Platform Health | AI Platform Admin / DevOps | Connector status, telemetry freshness, module health, configuration drift detail |
  | Compliance Mapping | Compliance Officer / Auditor | Control-to-framework mapping, evidence status, gap analysis by framework |
  | Module Coverage | Solution Admin | Installed modules, graduation status, prerequisite validation, data source inventory |
- **Navigation model:** Top-level persona selector (dropdown parameter) filters all tabs. Each tab has a time-range picker and workspace selector. Drill-through links from summary tiles to detail tables. Cross-tab links where a finding in one persona view is actionable in another.

#### 3. Severity and Confidence Model
- **Severity levels (aligned with Sentinel native enum):**
  | Severity | Criteria | Example |
  |----------|----------|---------|
  | High | Active misconfiguration exposing data or disabling a security control | Content filtering disabled on production Azure OpenAI |
  | Medium | Configuration drift from approved baseline; policy violation detected | Model version changed without approval |
  | Low | Informational drift or non-critical deviation | Diagnostic setting added (not removed) |
  | Informational | Telemetry health, baseline refresh, or coverage status | Watchlist baseline updated successfully |
- **Confidence levels:**
  | Confidence | Definition | Mapping |
  |------------|------------|---------|
  | High | Deterministic match against known-bad pattern or verified baseline violation | Exact Watchlist key miss or Azure Policy non-compliance |
  | Medium | Threshold or heuristic-based detection with tunable parameters | Anomalous token consumption exceeding 3σ over 7-day baseline |
  | Low | Behavioral anomaly or informational signal requiring analyst judgment | New agent registered by unfamiliar identity |
- **Composite priority:** `Severity × Confidence` determines default response path:
  - High × High → Auto-notify + queue for immediate triage
  - High × Medium → Auto-notify + analyst review within SLA
  - Medium × any → Standard SOC queue
  - Low / Informational → Dashboard visibility only (no alert by default, opt-in)
- **Rule metadata:** Every analytic rule declares `severity`, `confidence` (custom tag), governance domain, control ID, and required data sources in its YAML front matter.

#### 4. Lab Lifecycle and Cost Guardrails
- **Resource tagging (required on all validation resources):**
  | Tag | Value | Purpose |
  |-----|-------|---------|
  | `Environment` | `Validation` | Distinguish from production |
  | `Project` | `AIGovernanceSolution` | Cost attribution |
  | `Owner` | Deployer alias | Accountability |
  | `ExpiryDate` | ISO 8601 date (default: deploy date + 30 days) | Auto-cleanup eligibility |
  | `CostCenter` | Deployment parameter | Billing attribution |
- **Cost guardrails:**
  - Sentinel workspace: Free tier for first 10 GB/day ingestion (validation volumes expected well under this).
  - Logic Apps: Consumption plan (pay-per-execution) for validation; no always-on costs.
  - Azure Monitor action group: Budget alert at **$25/day** on the validation resource group. Configurable.
  - Security Copilot SCU: **Do not provision SCUs in validation** unless the Security Copilot optional module is explicitly being tested. Document estimated SCU cost per enrichment call.
  - No long-running compute (VMs, AKS, always-on App Services) in the solution design.
- **Lifecycle:**
  - Validation resources are ephemeral. Deployment script tags resources with `ExpiryDate`.
  - README documents manual cleanup; automated cleanup (Azure Automation runbook) is a Stage 2 enhancement.
  - Test data uses synthetic/sample events only — no production data in validation environment.

#### 5. CI / Release Gates
- **Required gates before any release (enforced in GitHub Actions):**
  | Gate | Tool | Blocking? |
  |------|------|-----------|
  | ARM/Bicep template validation | `az bicep build` + `az deployment group validate --mode Complete` | Yes |
  | KQL syntax validation | `kql-syntax-check` or equivalent parser; all `.kql` and inline rule queries must parse | Yes |
  | Solution package generation | `createSolutionV3.ps1` completes without error | Yes |
  | Watchlist schema validation | Schema files parse; required columns present; no breaking changes vs. prior version | Yes |
  | Secret scan | `gitleaks` or equivalent; zero findings | Yes |
  | GUID consistency | All content GUIDs are deterministic and match manifest | Yes |
  | Changelog entry | `CHANGELOG.md` updated for every MINOR+ release | Yes (MINOR+) |
  | Reviewer approval | At least one human reviewer approval on PR | Yes |
- **Recommended but non-blocking (first release):**
  - Workbook JSON schema validation
  - ASIM parser compatibility check
  - Deployment dry-run in validation workspace
- **Release artifact:** Tagged GitHub Release with solution package ZIP, SHA256 checksum, and release notes.

#### 6. Module Maturity Labels
| Label | Deployable? | Default State | Criteria |
|-------|-------------|---------------|----------|
| **Experimental** | No | Not included in package | Design phase; interface may change; no telemetry validation |
| **Preview** | Yes | Enabled (labeled in UI) | Meets graduation criteria; telemetry validated in at least one environment; schema may change; labeled `[Preview]` in all UI surfaces |
| **GA** | Yes | Enabled | Stable schema; validated across ≥2 environments; full documentation; breaking changes follow SemVer MAJOR |
| **Deprecated** | Yes (disabled) | Disabled | Replacement available; sunset date documented; migration guide published; removed after one MAJOR version |

- **Graduation path:** Experimental → Preview → GA. Modules cannot skip Preview. Deprecation can occur from any stage.
- **UI labeling:** Preview modules display `⚠️ Preview` badge in workbook tabs, rule names include `[Preview]` suffix, and deployment parameters include `enable<Module>Preview = true` (overridable to `false`).

#### 7. Handling of Unavailable or Unlicensed Services
- **Principle:** A missing license or connector is a **coverage gap**, never a false-compliant state.
- **Behavior matrix:**
  | Condition | Workbook | Analytic Rules | Playbooks | Health Check |
  |-----------|----------|---------------|-----------|-------------|
  | Connector not configured | "Not Configured" tile; no data panels | Deploy **disabled**; enable instructions in description | Deploy but skip execution; log skip reason | ⚠️ Yellow — gap documented |
  | License tier insufficient | "License Required" tile with SKU guidance | Deploy **disabled** | Deploy but skip; surface license requirement | ⚠️ Yellow — gap documented |
  | Table exists but empty (>7 days) | "No Data" tile with troubleshooting link | Enabled but suppressed (no false positives from empty joins) | Active but no incidents to trigger | 🔴 Red — data quality issue |
  | Service in different region | Functional (cross-region queries supported) | Enabled | Enabled | ✅ Green (note: cross-region latency) |
  | Preview service unavailable | "Preview Unavailable" tile | Deploy **disabled** | Deploy disabled | ⚪ Not Applicable |
- **Preflight check:** Deployment script runs a connector/table availability matrix and outputs a coverage report before enabling any module. Results are written to a deployment log and optionally to a Sentinel Watchlist for runtime health monitoring.

#### 8. Control ID Namespace
- **Format:** `AIGS-<Domain><NNN>`
  | Domain Code | Governance Function | Example |
  |-------------|-------------------|---------|
  | `CD` | Configuration Drift | `AIGS-CD001` — Azure OpenAI content filtering disabled |
  | `PA` | Posture Assessment | `AIGS-PA001` — Agent without required DLP policy |
  | `AM` | Audit Monitoring | `AIGS-AM001` — Unauthorized model deployment |
  | `RU` | Risky Usage | `AIGS-RU001` — Anomalous token consumption |
  | `IR` | Incident Response | `AIGS-IR001` — Auto-remediation execution audit |
- Numbering is sequential within domain. Control IDs are solution-owned and map many-to-many to framework controls (MCSB, NIST AI RMF).

#### 9. Content Naming Conventions
- **Analytic rules:** `[AIGS] <Domain> - <Description>` (e.g., `[AIGS] Config Drift - Content Filtering Policy Removed`)
- **Hunting queries:** `AIGS - Hunt - <Description>` (e.g., `AIGS - Hunt - Agents Registered by External Identity`)
- **Playbooks:** `AIGS-<Type>-<NNN>-<ShortName>` (e.g., `AIGS-Notify-001-TeamsAlert`, `AIGS-Auto-001-RestoreDiagnostics`)
- **Workbooks:** `Microsoft Sentinel - AI Governance Solution` (single workbook with persona tabs)
- **Watchlists:** `AIGS_<BaselineName>` (e.g., `AIGS_ApprovedModels`, `AIGS_ApprovedAgents`, `AIGS_ContentFilterPolicies`)

#### 10. Deployment Parameter Naming
- **Convention:** camelCase, descriptive, grouped by concern.
  | Parameter | Type | Default | Required? |
  |-----------|------|---------|-----------|
  | `workspaceResourceId` | string | — | Yes |
  | `location` | string | `eastus` | Yes (with preflight) |
  | `notificationTeamsWebhookUrl` | string | — | Yes (if notification module enabled) |
  | `approverGroupObjectId` | string | — | Yes (if approval module enabled) |
  | `emailFallbackRecipients` | string | — | No |
  | `metadataRetentionDays` | int | `90` | No |
  | `contentRetentionDays` | int | `30` | No |
  | `enableContentIngestion` | bool | `false` | No |
  | `enableSecurityCopilotModule` | bool | `false` | No |
  | `enablePreviewModules` | bool | `true` | No |
  | `tagEnvironment` | string | **REQUIRED** | **Yes** (corrected: no default; forces conscious selection between `Validation` or `Production`) |
  | `tagOwner` | string | — | No |
  | `uamiResourceId` | string | — | No (created by bootstrap if blank) |

**Correction Applied (Switch, 2026-07-16T18:11:00):** `tagEnvironment` changed from default `Production` to **required with no default**. Rationale: During development, all deployments target validation; a `Production` default risks tagging validation resources as production, triggering compliance policies and confusing cost attribution. See Correction 1 in Switch review.

#### 11. Approval Timeout Behavior
- **Default timeout:** 4 hours (configurable via deployment parameter `approvalTimeoutMinutes`, default `240`).
- **On timeout:** Escalate to email fallback recipients. Log `Approval Timed Out` in Sentinel incident comments. **Do NOT auto-approve.** Incident remains in `New` status for manual triage.
- **On rejection:** Log `Approval Rejected by <identity>` with timestamp. Close remediation workflow. Incident updated to `Active` for analyst follow-up.

#### 12. Content Versioning
- **Scheme:** Semantic Versioning (SemVer) — `MAJOR.MINOR.PATCH`
  - **MAJOR:** Breaking parameter, schema, or Watchlist changes requiring migration.
  - **MINOR:** New modules, rules, hunting queries, or workbook tabs. Non-breaking.
  - **PATCH:** Bug fixes, KQL tuning, documentation updates.
- **Initial release:** `1.0.0`
- **Pre-release:** `0.x.y` during development; `1.0.0-preview.N` for preview packages.

#### 13. Repository Branch Strategy
| Branch | Purpose | Protection |
|--------|---------|------------|
| `main` | Release-ready; tagged releases cut from here | Required PR review, CI gates pass |
| `dev` | Integration branch; PRs from feature branches | CI gates (lint + validate) |
| `feature/<name>` | Individual work items | None (developer discretion) |
| `release/v<X.Y>` | Release stabilization (created when cutting a release) | Same as `main` |

- **Tags:** `v<MAJOR>.<MINOR>.<PATCH>` on `main` for releases.

#### 14. GUID Management
- **Solution GUID:** `f1de974b-f438-4719-b423-8bf704ba2aef` (already assigned).
- **Content GUIDs:** Deterministic UUIDv5 generated from the solution namespace UUID + content item ID (e.g., rule name). This ensures reproducibility across builds and environments.
- **GUID registry:** Maintain a `guids.json` manifest in the solution package folder. CI validates all deployed GUIDs match the registry.

#### 15. Watchlist Schema Conventions
- **Column naming:** PascalCase (e.g., `ModelName`, `ResourceId`, `ApprovedVersion`).
- **Required columns per Watchlist:**
  | Column | Type | Purpose |
  |--------|------|---------|
  | `ItemKey` | string | Unique lookup key (Watchlist `SearchKey`) |
  | `LastUpdated` | datetime | Baseline version timestamp |
  | `BaselineVersion` | string | Git commit SHA or tag |
  | `Status` | string | `Active` / `Deprecated` |
- **Source of truth:** CSV files in `Data/Watchlists/` under version control. Deployment script uploads to Sentinel Watchlists API.

#### 16. KQL Coding Standards
- Use `let` bindings for readability and reuse.
- Comment the data contract (required table, expected columns, ASIM parser if applicable) at the top of every query.
- Use `_Im*` ASIM functions where normalized sources exist; document the specific ASIM schema version.
- Indent with 4 spaces; no tabs.
- Time filters use `ago()` with parameterizable lookback (default `1d` for rules, `14d` for hunts).
- Avoid `*` projections; explicitly name columns.
- Include `// Control: AIGS-XX###` comment linking to the control ID.

#### 17. Connector Configuration Guidance Format
- Each module includes a `PREREQUISITES.md` with:
  ```
  ## <Module Name> Prerequisites
  - **Connector:** <ConnectorId> (<Display Name>)
  - **Required License:** <SKU> (e.g., E5 Security, Agent 365)
  - **Required Roles:** <Entra/Azure RBAC roles for connector setup>
  - **Expected Table:** <TableName>
  - **Verification Query:** <KQL one-liner to confirm data presence>
  - **ASIM Parser:** <Parser name if applicable, or "N/A">
  - **Known Limitations:** <Any caveats>
  ```

#### 18. Playbook Failure Handling
- All playbooks implement structured error handling (try/catch in Logic App).
- On failure: write error details to Sentinel incident comment, send Teams notification to ops channel, and log to `AzureDiagnostics` (Logic App diagnostics).
- Idempotency: all remediation actions must be safely re-runnable.
- Circuit breaker: if a playbook fails 3 consecutive times on the same incident, suppress retries and escalate.

#### 19. ARM API Version Policy
- Use the latest **GA** API version for each resource type at time of authoring.
- Pin versions explicitly in templates (no `latest` or floating references).
- Document pinned versions in a `api-versions.md` reference file.
- Review and update API versions at each MINOR release.

#### 20. Diagnostic and Operational Logging
- All playbooks enable Logic App diagnostic settings (send to the Sentinel workspace).
- Deployment script logs its actions to a deployment log file (local) and optionally to a `AIGS_DeploymentLog` Watchlist.
- Health-check workbook tab queries Logic App run history and Watchlist freshness.

---

## Irreversible or Cost-Bearing Decisions — GATED FOR HUMAN RETURN

The following decisions require explicit human approval before execution and are maintained in this section as a permanent audit trail. These represent strategic commitments that cannot be reversed without organizational impact.

| Decision | Why Gated | Risk | Status |
|----------|-----------|------|--------|
| **Content Hub publication** | Creates a public marketplace record; cannot be retracted without Microsoft involvement | Reputational, legal | ⏸️ Blocked pending human approval |
| **Upstream Azure-Sentinel PR** | Public contribution; triggers community review and Microsoft repo standards | Reputational, maintenance commitment | ⏸️ Blocked pending human approval |
| **Production tenant deployment** | Deploys to environment with real organizational data and compliance obligations | Data governance, operational | ⏸️ Blocked pending human approval |
| **SCU provisioning for Security Copilot** | Consumption-based billing; costs accrue immediately upon provisioning | Financial | ⏸️ Blocked pending human approval |
| **Marketplace publisher registration** | Legal/organizational commitment to Microsoft Partner Center | Legal, identity | ⏸️ Blocked pending human approval |
| **Custom domain / external branding** | Public identity commitment | Reputational | ⏸️ Blocked pending human approval |
| **Production UAMI role assignments** | Grants service identity permissions in production Entra/Azure | Security, least-privilege validation needed | ⏸️ Blocked pending human approval |

**Return Gate:** These items remain blocked until x3nc0n or a designated approver returns with explicit authorization.

---

## Discovery Review Decisions (Archived for Reference)

These decisions were reached during the discovery phase and are now superseded by the interactive walkthrough decisions and Morpheus architecture defaults above. They are preserved for reference and historical continuity.

### Discovery: AI Governance Architecture Discovery (APPROVED WITH CORRECTIONS)
- **Status:** Approved by Switch (discovery review); corrections applied
- **Owner:** Morpheus (discovery); x3nc0n (decision)
- **Reference:** See architecture defaults §1-3, §6, §8 above for implementation details.

### Discovery: Telemetry Feasibility & Control Prioritization (APPROVED WITH CORRECTIONS)
- **Status:** Approved by Switch (discovery review); corrections applied
- **Owner:** Trinity (discovery); x3nc0n (decision)
- **Reference:** See architecture defaults §7, §16-17 above for implementation details.

### Discovery: Sentinel Solution Packaging & Schema (APPROVED WITH CORRECTIONS)
- **Status:** Approved by Switch (discovery review); corrections applied
- **Owner:** Neo (discovery); x3nc0n (decision)
- **Reference:** See architecture defaults §5, §14, §15 above for implementation details.

### Discovery: Playbook Implementation Feasibility (APPROVED WITH CORRECTIONS)
- **Status:** Approved by Switch (playbook review); corrections applied
- **Owner:** Tank (discovery); x3nc0n (decision)
- **Reference:** See architecture defaults §18-19 above for implementation details.

### Discovery: Verified Table Names Reference
- **Status:** Established by Switch review consolidation
- **Approved Tables for MVP:** `CopilotActivity`, `AgentsInfo`, `AzureActivity`, `AzureDiagnostics`, `AuditLogs`

### Discovery: Playbook MVP Path
- **Status:** Established by Tank/Switch consensus
- **Approved MVP Playbooks (Week 1 Targets):**
  1. **PB-AUTO-01:** AutoRemediate-DiagnosticLoggingRestored
  2. **PB-NOTIFY-01:** Notify-AI-GovernanceTeam

---

## Governance

- **Authority:** Interactive user decisions + autonomous Morpheus architecture defaults (with Switch corrections) establish binding strategic and operational direction
- **Gated Items:** Seven irreversible/cost-bearing decisions remain explicitly blocked until human return (see table above)
- **Amendment Process:** Material changes to active decisions require team consensus; this document serves as the source of truth
- **Versioning:** Updated at each major decision consolidation; timestamps and authors recorded for each entry
- **Archive:** Discovery-phase decisions preserved for reference; implementation defaults guide all content development

**Last Updated:** 2026-07-16T18:15:10.970-07:00  
**Consolidation:** Morpheus autonomous resolution approved by Switch with one correction applied  
**Decision Count:** 45 active (18 interactive + 20 architecture defaults + 7 gated); 6 archived (discovery phase)
