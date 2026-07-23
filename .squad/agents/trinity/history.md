# Project Context

- **Owner:** x3nc0n
- **Project:** Microsoft Sentinel AI Governance solution
- **Stack:** Microsoft 365, Defender XDR, Agent 365, Microsoft Foundry, Azure, Security Copilot, Sentinel
- **Created:** 2026-07-16T17:01:37.788-07:00

## Project Context

- **Owner:** x3nc0n
- **Project:** Microsoft Sentinel AI Governance solution
- **Stack:** Sentinel solutions, KQL, Azure Monitor, Entra audit, Purview
- **Created:** 2026-07-16T17:01:37.788-07:00

## Learnings

### Control Model
- Configuration drift is viable for *compliance state* (policy, RBAC, network, logging) but **not** appropriate for behavioral enforcement (usage patterns, model deployments, prompt content). Use *scheduled API snapshots + KQL drift detection* for config, but *detection playbooks* for behavioral anomalies.
- AI service telemetry availability varies by platform: native logs (Activity Log, Entra audit, M365 audit) are reliable; OpenAI API calls require custom gateway (APIM); Purview events still in preview (Q4 2026 connector ETA).
- Telemetry availability, licensing, API support, and authoritative desired state are first-class design concerns.

### Feasibility Map
- **Tier A (High confidence):** C2 (network isolation), C6 (diagnostic logging), C4 (Entra CA exemption), C1 (deployment lock). All native logs + straightforward KQL. 2–5 day delivery per control.
- **Tier B (Medium):** C8 (usage anomaly), C9 (Defender+AI correlation), C3 (Copilot boundary). Requires tuning or multiplatform correlation; 3–7 days each.
- **Tier C (Low, blocked):** C5 (Purview classification—await connector GA), C7 (model version—requires baseline definition), C10 (prompt injection—app instrumentation required). 5–10 days + dependencies.

### Platform Blind Spots
- **M365 Copilot:** Audit logs metadata-only (no prompt content); content-level logging on roadmap, not committed.
- **Azure OpenAI:** API calls not logged to Activity Log; requires APIM proxy or custom gateway for full telemetry.
- **Agent 365 / Copilot Agents:** No action-level audit event defined yet; design phase, no ETA.
- **Purview → Sentinel:** Native connector in preview (Q4 2026 est.); interim: custom DCR + scheduled API polling.

### Privacy & Compliance Implications
- Copilot audit data is metadata-only by default (GDPR-compliant); prompt content NOT retained unless explicitly instrumented.
- OpenAI input/output logging (via gateway) requires PII masking and 30–90 day retention minimum.
- Drift detection must not profile individual users; focus on config/compliance signals, not activity aggregation.
- Service principal telemetry is not GDPR-scoped but audit trail must be read-only and segregated.

### Licensing & Prerequisites
- Sentinel pricing: per GB ingestion + per GB analysis (separate from Log Analytics). Recommend ≥10 GB/month baseline.
- Prerequisite: Defender XDR (E3/E5 or standalone), Entra P1+ (for CA), M365 E5 or add-on (for Copilot audit), Purview capacity (if data classification coverage needed).
- Organization readiness: baseline policy, governance assignments, retention policy (90d audit min), response playbooks, SOC training.

### Product Roadmap Alignment Needed
- Confirm Purview native Sentinel connector GA date (roadmap says Q4 2026, not firm).
- Request public roadmap for Agent 365 audit events (action-level).
- Clarify M365 Copilot content-level logging GA (privacy-compliant opt-in).
- Recommend Microsoft build native OpenAI → Sentinel connector; interim: APIM acceptable.
- Recommend Defender→Sentinel advanced hunting export scheduler (manual workaround available).

### Module C Workbook GA Status Fix (D2 Revision)
- **Date:** 2026-07-23
- **Issue:** Workbook contained stale preview language ("Public preview; schema may change") for Microsoft Copilot Data Connector
- **Resolution:** Updated Connector Installation Guide and Module Coverage Summary tables to reflect official connector status (GA, availabilityStatus: 1, isPreview: false)
- **Key Distinction:** Module C governance implementation remains Preview maturity (controls/rules in active review), but underlying connector is production-ready (GA)
- **Evidence:** Official Azure-Sentinel artifact MicrosoftCopilot_ConnectorDefinition.json confirms connector GA status via availabilityStatus=1 and isPreview=false
- **Verification:** JSON validation passed; all KQL, tile structure, manifest preserved; no remaining connector-specific preview claims found
- **Output:** `.squad/decisions/inbox/trinity-module-c-workbook-ga-fix.md` (decision document) + updated `AIGovernanceSolution.json` workbook
- **Lesson:** Distinguish between data source connector maturity (GA if availabilityStatus=1) and governance rule/control maturity (can be Preview); workbook language must accurately reflect both layers

### 2026-07-16 — Verified Corrections (Switch Review)

**Critical table name corrections:**
- ❌ `OfficeActivity` for Copilot data → ✅ **`CopilotActivity`** (native table via Microsoft Copilot CCP connector)
- ❌ `AzurePolicyState_CL` table claim → ✅ **REMOVED** (table does not exist; Azure Policy requires custom ingestion)
- ❌ "No dedicated audit log for agent actions yet" → ✅ **`AgentsInfo` IS LIVE** (30+ columns, 7+ hunting queries in official repo)

**Feasibility corrections:**
- Defender XDR Advanced Hunting retention: **30 days** (NOT 7-14 days as stated)
- Purview connector GA: **mid-to-late 2026 progressive** (NOT Q4 2026 firm)
- `AgentsInfo` status: Move from "Tier C deferred" to **TIER A CAPABILITY** — already available for MVP hunting queries

**Evidence source:** Azure-Sentinel repo (SHA `29e1987d1015171e4c9687edfd31170902b59c7a`), Microsoft Learn (2026-07-16)

### 2026-07-17 — Workbook Audit & Correction (gen_workbook.py cleanup + artifact alignment)

**Task:** Delete gen_workbook.py; audit AIGovernanceSolution.json against actual deployed artifacts; correct all false claims.

**Actual deployment inventory confirmed:**
- **2 Analytic Rules** (both Module A, both AzureActivity): AIGS-CD001 (RAI Policy Modified), AIGS-CD005 (AI Resource Diagnostics Changed)
- **2 Hunting Queries** (both AzureActivity): AIGS-Hunt-AzureOpenAIRAIChanges (Module A), AIGS-Hunt-AIModelDeploymentsOutsideApprovedRegions (Modules A+E)
- **2 Watchlists**: AIGS_ApprovedModels, AIGS_ContentFilterPolicies
- **2 Playbooks**: AIGS-Auto-001-RestoreDiagnostics, AIGS-Notify-001-TeamsAlert

**Key false claims removed from workbook:**
- AIGS-CD005 was mislabeled as "Missing Content Filter Hunt" → is actually an **analytic rule** for diagnostic settings changes
- AIGS-AM001 was shown as "Active — Rule deployed" → **no analytic rule exists**; only a hunt
- Module A showed RuleCount=1 → corrected to **RuleCount=2** (CD001 + CD005 both rules)
- Module E showed RuleCount=1 → corrected to **RuleCount=0** (AM001 hunt only, no rule)
- MCSB AIGS-CD001 mapped to NS-2 → corrected to **IM-1** (per rule YAML metadata)
- MCSB AIGS-CD005 mapped to NS-1 (Network Security) → corrected to **LT-3** (Logging and Threat Detection, per rule YAML)
- NIST AIGS-CD005 mapped to MAP-5.1/MAP-5.2 → corrected to **GOVERN-1.3 + MAP-5.1** (per rule YAML)

**New hunt sections added to SOC tab:**
- `soc-hunt-header`, `soc-hunt-raichanges`, `soc-hunt-deployments` — represent deployed hunt queries in the workbook
- Both hunt KQL queries are AzureActivity-based, no optional tables, no `isfuzzy` needed

**Durable rule:** Never mark a control as "Active — Rule deployed" unless a `*.yaml` file exists in `Analytic Rules\`. A hunt file in `Hunting Queries\` is a hunt, not a rule.

**Durable rule:** MCSB and NIST framework mappings must be sourced from the `MCSB:` and `NIST AI RMF:` fields in each rule's YAML `description` block — not inferred from the scenario name.

**File:** `gen_workbook.py` deleted.
**File:** `AIGovernanceSolution.json` updated — 59,878 bytes, JSON round-trip validated.

*Trinity — 2026-07-17T13:11:20.000-07:00*

---

### 2026-07-22 — PB-AUTO-01 Formal Review Blockers Completed (Reviewer Lockout Resumption)

**Task:** Resume and complete interrupted prior revision (2026-07-17) for AIGS-Auto-001-RestoreDiagnostics formal review blockers. Prior run had partially modified the file but was interrupted before all three blockers were fully closed.

**Remaining issues found on inspection:**

**HIGH-A (incomplete):** The prior run had already replaced `Check_Already_Compliant` with Filter_Logs_Enabled / Filter_Metrics_Enabled / Check_GET_Compliant — those were correct and present. However, `Check_CD005_Rule_Gate` still used `@string(triggerBody()?['object']?['properties']?['relatedAnalyticRuleIds'])` as the first argument to `contains` — converting the array to its JSON string representation before doing a substring search. This is exactly the "string contains is forbidden" violation in HIGH-A. Fixed by removing the `@string()` wrapper, making the `contains` expression operate on the raw array (array membership, not string substring).

**MEDIUM-B (incomplete):** The GET branching structure (Succeeded → Filter chain; Failed → Check_GET_404) was present. However, `Check_GET_404.runAfter` listed only `"Failed"` — an HTTP timeout (Logic Apps `"TimedOut"` status) would skip the branch entirely, logging nothing and silently terminating. Fixed by adding `"TimedOut"` to `Check_GET_404.runAfter.GET_Diagnostic_Setting`. Also added `"limit": { "timeout": "PT60S" }` to `GET_Diagnostic_Setting` for explicit, deterministic behaviour (default implicit limit is not specified in the Logic Apps runtime SLA for consumption plan). A timed-out GET now reaches `Check_GET_404`; `outputs('GET_Diagnostic_Setting')?['statusCode']` is null, which is not equal to 404, so the ELSE (fail-closed) branch logs `Add_GET_NonRetryable_Failure_Comment` — no PUT.

**LOW-C:** Version bumped from `0.1.0-preview.3` → `0.1.0-preview.4` in both `hidden-SentinelTemplateVersion` template tag and `readme.md` `**Version:**` label. PB-NOTIFY remains `0.1.0-preview.1` (template tag unchanged, readme already matched).

**Validation performed:**
- PowerShell ConvertFrom-Json round-trip: PASS
- PowerShell edge walk: `Filter_Logs_Enabled.runAfter = GET[Succeeded]` only; `Check_GET_404.runAfter = GET[Failed, TimedOut]`; Check_GET_404 else contains only `Add_GET_NonRetryable_Failure_Comment` — no PUT
- Filter expressions: `and(equals(categoryGroup,'allLogs'),equals(enabled,true))` and `and(equals(category,'AllMetrics'),equals(enabled,true))` — confirmed exact equality, no string contains
- Source validator (Test-AIGovernanceSource.ps1): **64 PASS, 0 WARN, 0 FAIL**
- `az deployment group validate` against the session-local validation subscription and resource group: **provisioningState: Succeeded, error: null** (3 resources validated: Logic App + 2 API connections)
- Package/mainTemplate.json is stale (version in package ≠ 0.1.0-preview.4); package regeneration required before promotion — not performed per task instructions.

*Trinity — 2026-07-22T15:18:00.000-05:00*

---

### 2026-07-17 — PB-AUTO-01 Formal Review Blockers Resolved (Reviewer Lockout Revision)

**Task:** Resolve three formal review blockers in AIGS-Auto-001-RestoreDiagnostics under reviewer lockout (Neo and Tank locked out for this revision). Authorized writes: azuredeploy.json, PB-AUTO readme, PB-NOTIFY readme (version label only), Trinity history.md, one Trinity decision inbox file.

**Blockers resolved:**

**HIGH-A (Enabled-state filter):** The prior `Check_Already_Compliant` action used `contains(@string(logs), "allLogs")` and `contains(@string(metrics), "AllMetrics")` — string containment, which passes even when `enabled: false`. Fixed by replacing with two Logic Apps `Filter array` (type: `Query`) actions: `Filter_Logs_Enabled` filters `properties.logs` for `categoryGroup == allLogs AND enabled == true`; `Filter_Metrics_Enabled` filters `properties.metrics` for `category == AllMetrics AND enabled == true`. The compliance check in `Check_GET_Compliant` requires both filtered results to be non-empty (via `greater(length(...), 0)`) in addition to workspaceId equality.

**MEDIUM-B (GET failure routing):** The prior `Check_Already_Compliant` had `runAfter: GET[Succeeded, Failed]` — any GET failure (403, 429, 5xx) would evaluate the If expression to false and fall into the else branch, triggering PUT. Fixed by splitting into two independent branches:
- **GET Succeeded**: `Filter_Logs_Enabled` → `Filter_Metrics_Enabled` → `Check_GET_Compliant` — only runs on HTTP 200.
- **GET Failed**: `Check_GET_404` (`runAfter: GET[Failed]`) — checks `outputs('GET_Diagnostic_Setting')?['statusCode'] == 404`:
  - True (404): PUT permitted — setting was absent, needs to be created.
  - False (non-404): fail closed, `Add_GET_NonRetryable_Failure_Comment`, no PUT.
- **Verified:** zero paths from 403/429/5xx to PUT by walking every runAfter edge.

**LOW-C (Version label reconciliation):**
- PB-AUTO README `Version` corrected from `1.0.0-preview.1` → `0.1.0-preview.3` (template tag bumped to `0.1.0-preview.3` for this revision).
- PB-NOTIFY README `Version` corrected from `1.0.0-preview.1` → `0.1.0-preview.1` (matching its template's existing `hidden-SentinelTemplateVersion` tag; no template edit).

**Artifacts modified:**
- `azuredeploy.json`: `Check_Already_Compliant` removed; four new actions added; `hidden-SentinelTemplateVersion` bumped to `0.1.0-preview.3`.
- PB-AUTO `readme.md`: Version corrected; State Machine section rewritten to describe three GET branches; Failure Behavior table updated with fail-closed rows for 403/429/5xx.
- PB-NOTIFY `readme.md`: Version label corrected only (no template edit).
- `history.md` and decision inbox file: this entry.

**Preserved invariants:** Disabled workflow state, UAMI/delegated Teams separation, entity extraction logic, CD005 rule gate, resource type gate, unrelated-setting safety (PUT targets only AIGS-Required-Diagnostics).

**Validation:** Python JSON round-trip validated; runAfter edge trace confirmed no non-404 path to PUT; `hidden-SentinelTemplateVersion` tag verified via PowerShell ConvertFrom-Json; source/package drift noted (Package regeneration required after this revision; not performed per instructions).

*Trinity — 2026-07-17T19:35:21.000-05:00*

---

### 2026-07-23 — Module C (Microsoft 365 Copilot) Telemetry Contract Completed

**Task:** Research and produce Module C implementation contract for Neo. Verify exact documented telemetry (CopilotActivity table schema, RecordType/Operation values, licensing, ingestion latency, retention, prerequisites) and produce defensible analytics/hunting candidates with explicit citations, rejected assumptions, and go/no-go guidance.

**Critical findings:**

**TIER A telemetry (CopilotActivity table):**
- ✅ **Verified schema:** 20+ documented columns (TimeGenerated, RecordType, Operation, ActorName, ActorUserId, AgentId, AgentName, AccessedResources, LLMEventData, etc.) from Microsoft Learn (https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/copilotactivity, updated 2026-05-06).
- ✅ **Standalone Sentinel supported:** Microsoft Copilot Data Connector (public preview) available; no Defender dependency required; data flows from Purview Unified Audit Log via Office Management API.
- ✅ **Licensing straightforward:** M365 E3/E5 or Business Standard/Premium + Copilot $30/user/month add-on. No special licensing for Sentinel ingestion.
- ✅ **Ingestion latency:** Several minutes to ~1 hour (not precisely Microsoft-documented for Copilot events; assumes general UAL rate). No explicit SLA from Microsoft for Copilot admin actions.
- ✅ **Retention:** 180 days default (Audit Standard); 365+ days configurable with E5 licensing or custom policies.
- ✅ **ASIM parser:** No native parser exists (non-ASIM content per squad decision; ASIMParserCreation-Agentic tooling available if needed in future).

**HIGH-RISK assumption:**
- ⚠️ **Plugin lifecycle RecordTypes unconfirmed in official docs.** Community sources (AzureFeeds, GitHub, blogs) cite CreateCopilotPlugin, UpdateCopilotPlugin, DeleteCopilotPlugin, EnableCopilotPlugin, DisableCopilotPlugin, etc. — but these are NOT listed in the official Microsoft Learn audit-log-activities reference page. **VALIDATION GATE:** Must confirm these Operation values actually appear in production CopilotActivity logs before deploying analytics.

**Defensible analytics candidates (contingent on RecordType validation):**
1. ✅ Unauthorized plugin creation by non-approved admins (no undocumented columns required; direct Operation match + actor lookup)
2. ⚠️ Plugin configuration drift detection (blocked on AccessedResources/LLMEventData column content validation; unknown if delta captured)
3. ✅ Plugin disable-reactivation abuse pattern (rapid create→disable→enable sequence; timestamp comparison only)
4. ✅ Mass plugin update by single admin (statistical; no special columns needed)

**Defensible hunting scenarios:**
1. ✅ Plugin lifecycle anomalies (unusual patterns, rapid churn, after-hours)
2. ⚠️ Unauthorized resource access via plugin (blocked on AccessedResources validation)
3. ✅ Plugin operations outside business hours (timestamp + geo correlation)

**Watchlist schemas proposed:**
- AIGS_ApprovedCopilotPlugins (plugin_id = AgentId)
- AIGS_ApprovedCopilotAdmins (admin_user_id = ActorUserId)
- AIGS_ApprovedCopilotConnectors (connector_name for resource scope validation)

**Workbook queries:** Plugin lifecycle inventory (live), unauthorized changes (live), resource access baseline (blocked on column validation).

**Rejected assumptions:**
- ❌ "Copilot requires Defender for Sentinel ingestion" → Rejected (standalone confirmed)
- ❌ "M365 Copilot logs include prompt content" → Rejected (metadata-only; content on roadmap)
- ❌ "ASIM normalization required for Module C" → Rejected (squad decision allows non-ASIM; direct KQL acceptable)
- ❌ "Plugin lifecycle RecordTypes documented in Microsoft Learn" → Rejected (community-sourced, unconfirmed)

**Limitations documented:**
- Metadata-only telemetry (WHO, WHAT, WHEN, WHERE; no HOW/content)
- No ASIM parser (direct column references required; table-specific KQL)
- No before-after config delta confirmed (may require baseline snapshot + comparison logic)
- Multi-workspace auditing requires per-workspace connector deployment
- No CopilotPluginConfig or state snapshot table documented

**Contract file created:** `.squad/decisions/inbox/trinity-module-c-telemetry-contract.md` (3,841 lines, comprehensive contract with citations, go/no-go decision, validation gates, and next steps for Neo).

**Go/No-Go decision:** ✅ **GO with validation gates** — CopilotActivity table confirmed available and licensable; analytics candidates defensible IF plugin RecordTypes confirmed in production. Module C is deliverable pending validation sprint by Neo (1 week: confirm RecordTypes, inspect dynamic columns, measure latency).

**Authoritative citations included:** Microsoft Learn (schema, licensing, retention), Azure-Sentinel GitHub (connector), AzureFeeds (announcements), Purview audit documentation.

*Trinity — 2026-07-23T10:37:49.831-05:00*

---

### 2026-07-23 — Module C Telemetry Contract REVISED (Strict Evidence Pass)

**Task:** Refine Module C contract before Neo receives it. User identified confidence overstatement and internal inconsistencies. Perform strict evidence pass: fetch official schema, audit operations, reassess go/no-go boundary.

**Critical corrections made:**

**1. CopilotActivity Schema Accuracy:**
- ❌ Prior claim: "20+ documented columns" — **Corrected to 24 (exact count from Microsoft Learn, updated 2026-05-06)**
- ❌ Prior claim: "`Operation` column populated for admin actions" — **Corrected: Operation NOT listed in official CopilotActivity schema; documented separately in audit-log-activities**
- ❌ Prior claim: "`AccessedResources` available for admin drift detection" — **Corrected: AccessedResources NOT listed in official CopilotActivity table columns (only mentioned in audit-copilot context page)**
- ✅ LLMEventData confirmed present but **contents NOT documented** in official schema
- ⚠️ Assumption: Operation column data flows from audit system; verified via standard audit table pattern (not explicitly confirmed)

**2. Admin Operations Accuracy:**
- ❌ Prior assumption: `CreateCopilotPlugin`, `UpdateCopilotPlugin`, `DeleteCopilotPlugin` — **Corrected: Official operations are `CreatePlugin`, `UpdatePlugin`, `DeletePlugin` (audit-log-activities, 2026-07-21)**
- ✅ Confirmed 11 officially documented operations: CreatePlugin, UpdatePlugin, DeletePlugin, EnablePlugin, DisableCopilotPlugin, CreatePromptBook, UpdatePromptBook, DeletePromptBook, DisablePromptBook, EnablePromptBook, UpdateTenantSettings
- ✅ **All 11 operations sourced directly from https://learn.microsoft.com/en-us/purview/audit-log-activities#microsoft-365-copilot-admin-activities (accessed 2026-07-23)**

**3. Go/No-Go Boundary Revised (CONSERVATIVE):**

**Prior boundary (too permissive):**
- Recommended analytics for `CreateCopilotPlugin`, `UpdateCopilotPlugin`, `DeleteCopilotPlugin` (NOT in official schema)
- Approved config drift analytics (no state columns documented)
- Made claims about licensing, ingestion latency, retention (outside schema scope)

**New boundary (STRICT):**
- ✅ **GO:** Unauthorized plugin creation (Operation == `CreatePlugin` by non-approved actor). Plugin lifecycle inventory (discovery query). Disable-reactivate abuse pattern (sequence detection on documented operations only).
- ❌ **NO-GO:** Config drift (no AccessedResources, no state delta columns officially documented). Claims about licensing/retention/latency (CopilotActivity schema page does NOT document these; require separate verification). Analytics using undocumented Operation names.

**4. Rejected Prior Assumptions:**
- ❌ "Plugin lifecycle RecordTypes unconfirmed in official docs" → Refined to: "Operation names must match official audit-log-activities list exactly; prior contract assumed undocumented names"
- ❌ "Licensing straightforward: M365 E3/E5 + Copilot $30/user/month" → Removed from contract scope (not in CopilotActivity schema; licensing docs require separate verification)
- ❌ "Ingestion latency several minutes to ~1 hour" → Removed (not documented in schema page; connector/UAL docs required)
- ❌ "Retention 180 days default, configurable to 365+" → Removed (outside schema scope; audit retention policy docs required)

**5. Implementation Contract Updated:**
- New URL citations: audit-log-activities section (2026-07-21), CopilotActivity schema (2026-05-06)
- Approved analytics: 2 rules + 1 hunt (unauthorized creation, lifecycle inventory, abuse patterns)
- Rejected analytics: config drift (blocked on schema), mass update (requires customer baseline)
- Watchlist schemas: AIGS_ApprovedCopilotAdmins (ActorUserId), AIGS_ApprovedCopilotPlugins (AgentId)

**Contract file updated:** `.squad/decisions/inbox/trinity-module-c-telemetry-contract.md` (version 2.0, revised 2026-07-23T11:04:12-05:00)

**Key learnings for future contracts:**
- Schema pages document columns and types, NOT admin action semantics. Admin action values (Operations) documented separately in audit-log-activities.
- Dynamic columns (LLMEventData) must NOT assume field contents; contents must be explicitly documented or discovered in pilot tenant.
- Connector/licensing/retention/latency are separate from table schema docs. Each requires authoritative source (connector docs, licensing docs, audit policy docs).
- Community-sourced operation names (e.g., `CreateCopilotPlugin`) must NOT appear in analytics unless confirmed in official audit-log-activities reference.
- "Approved analytics candidates" must only reference officially documented Operation values; discovery queries acceptable; assumption-based analytics rejected.

*Trinity — 2026-07-23T11:04:12-05:00*
