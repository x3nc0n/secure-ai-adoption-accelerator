# Project Context

- **Owner:** x3nc0n
- **Project:** Microsoft Sentinel AI Governance solution
- **Stack:** Sentinel solution validation, KQL tests, ARM templates, CI checks
- **Created:** 2026-07-16T17:01:37.788-07:00

## Learnings

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
