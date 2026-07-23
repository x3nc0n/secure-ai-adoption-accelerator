---
name: "sentinel-fail-closed-watchlist"
description: "KQL analytic rules that join a Sentinel Watchlist must be fail-closed: an absent or template-only watchlist must produce zero results, never a flood of false positives."
domain: "detection-engineering"
confidence: "high"
source: "earned (Modules A, B, C across AIGS solution; validated against Sentinel Watchlist _GetWatchlist behavior)"
---

## Context

Every analytic rule in the AI Governance Solution that uses a Watchlist as a detection baseline
must be **fail-closed**: if the watchlist is absent, empty, or contains only `Status=Template`
rows, the rule must produce **zero** results. This prevents a fresh deployment from flooding the
SOC with false positives before the customer has populated their baselines.

This applies to all modules (A: AIGS_ContentFilterPolicies, B: AIGS_ApprovedAgents,
C: AIGS_ApprovedCopilotPlugins / AIGS_M365CopilotBaseline, and any future watchlist-gated rule).

## Patterns

### Required Pattern: materialize + inner join

```kql
// FAIL-CLOSED: inner join on Active watchlist entries only.
// If watchlist absent, empty, or all rows have Status != "Active", zero results produced.
let ApprovedBaseline = materialize(
    _GetWatchlist("AIGS_WatchlistName")
    | where Status =~ "Active"
    | project WL_JoinKey = tolower(JoinColumn), WL_OtherField = OtherField
);
SourceTable
| where TimeGenerated >= ago(queryPeriod)
| extend NormalizedKey = tolower(SourceJoinColumn)
| join kind=inner (ApprovedBaseline) on $left.NormalizedKey == $right.WL_JoinKey
// ... rest of detection logic
```

**Why `materialize()`:** Prevents `_GetWatchlist()` from being evaluated multiple times in
branches, which can cause inconsistent results. Always wrap in `materialize()` before joining.

**Why `| where Status =~ "Active"`:** Shipped template CSVs contain `Status=Template` rows.
Without this filter, template rows participate in the join and generate false positives immediately
on deployment. The validator (Check 6) enforces that shipped CSVs have no `Status=Active` rows.

**Why `kind=inner`:** An inner join against an empty set yields zero rows. If the watchlist is
not deployed, `_GetWatchlist()` returns an empty table, the inner join yields nothing, and the
rule is silent. This is the desired behavior.

### Anti-Pattern: leftanti / !in / !has (FAIL-OPEN)

```kql
// ❌ DANGER: fail-OPEN — fires on ALL events when approved list is empty
let ApprovedPlugins = _GetWatchlist("AIGS_ApprovedCopilotPlugins") | project PluginId;
SourceTable
| where ItemName !in (ApprovedPlugins)  // When ApprovedPlugins is empty, this is always true
```

When `ApprovedPlugins` is empty (watchlist absent or no Active rows), `!in (empty set)` is always
true, so EVERY event passes the filter. A fresh deployment with no watchlist data generates an
alert for every Copilot plugin event. This is the fail-open antipattern.

**Fix:** Convert to an inner join on Active entries only. The `leftanti` / `!in` pattern is only
safe when you first confirm the approved set is non-empty.

## Examples

### Module A (AIGS-CD001): Content Filter Policies
```kql
let BaselineResources = materialize(
    _GetWatchlist("AIGS_ContentFilterPolicies")
    | where Status =~ "Active"
    | project WL_AccountName = tolower(AccountName), WL_PolicyName = tolower(PolicyName)
);
AzureActivity
| ...
| join kind=inner (BaselineResources) on $left.AccountName == $right.WL_AccountName
```

### Module B (AIGS-CD002): Agent Config Drift
```kql
let ApprovedAgents = materialize(
    _GetWatchlist("AIGS_ApprovedAgents")
    | where Status =~ "Active"
    | project WL_AgentId = tolower(tostring(AgentId)), ...
);
AgentsInfo
| ...
| join kind=inner (ApprovedAgents) on $left.NormalizedAgentId == $right.WL_AgentId
```

## Anti-Patterns

- `| where JoinKey !in (_GetWatchlist("...") | project Key)` — fail-open when watchlist is empty.
- Calling `_GetWatchlist()` without `| where Status =~ "Active"` — template rows trigger false alerts.
- Calling `_GetWatchlist()` twice without `materialize()` — inconsistent results in branching queries.
- Shipping `Status=Active` rows in baseline CSVs — validator Check 6 rejects this; fixes the loop.
- Asserting watchlist non-emptiness before the join without `materialize()` — the empty-check and the join may see different snapshots.

## Shipped Baseline CSV Convention

Every watchlist CSV shipped with the solution must:
1. Include `ItemKey` and `Status` columns (enforced by validator Check 6).
2. Have zero `Status=Active` rows (enforced by validator Check 6).
3. Have at least one `Status=Template` row so the schema is self-documenting.

The customer populates Active rows after deployment to enable fail-closed detections.

## Validator Enforcement

Check 6 in `scripts/Test-AIGovernanceSource.ps1` enforces:
- ARM template shape and `itemsSearchKey` matches `guids.json` registry.
- CSV has `ItemKey` and `Status` columns.
- Zero `Status=Active` rows in shipped CSV.
- rawContent in ARM template is byte-identical to companion CSV.
