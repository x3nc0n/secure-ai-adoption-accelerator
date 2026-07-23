# API Versions Reference

This file documents the pinned ARM API versions used across all solution templates.
Review and update at each MINOR release per architecture default §19.

| Resource Type | API Version | Template Usage |
|---|---|---|
| `Microsoft.Logic/workflows` | `2019-05-01` | Playbook Logic App definitions |
| `Microsoft.Web/connections` | `2016-06-01` | Managed connector connections (Teams, Sentinel, ARM) |
| `Microsoft.ManagedIdentity/userAssignedIdentities` | `2023-01-31` | UAMI reference in bootstrap script |
| `Microsoft.Authorization/roleAssignments` | `2022-04-01` | RBAC assignments in bootstrap script |
| `Microsoft.OperationalInsights/workspaces` | `2022-10-01` | Workspace reads in validation scripts |
| `Microsoft.Insights/diagnosticSettings` | `2021-05-01-preview` | Diagnostic settings read/restore in PB-AUTO-01 |
| `Microsoft.SecurityInsights/incidents` | `2023-11-01` | Incident comment operations (via azuresentinel connector) |
| `Microsoft.SecurityInsights/watchlists` | `2023-11-01` | Watchlist deployment |
| `Microsoft.CognitiveServices/accounts/raiPolicies` | `2024-10-01` | Content filter policy read only (monitoring/investigation via GET; PB-AUTO-01 does not write to raiPolicies) |
| `Microsoft.CognitiveServices/accounts/deployments` | `2024-10-01` | Model deployment detection (Module E context) |

## Notes

- `2021-05-01-preview` for `diagnosticSettings` is the current GA stable version; "preview" is in the name but it is the
  generally available API. Monitor [aka.ms/armref](https://learn.microsoft.com/en-us/azure/templates/) for promotions.
- `Microsoft.Web/connections` `2016-06-01` is the long-stable version for Logic Apps managed connectors.
  No later GA version has superseded it for this resource type.
- All versions are pinned to GA at time of authoring (2026-07-17). No floating `latest` references are used.

## Review Schedule

| Release | Action |
|---|---|
| Each MINOR release | Review this file; update any versions that have new GA releases |
| Each MAJOR release | Audit all templates for deprecated API behavior |
