---
last_updated: 2026-07-16T23:51:56.293Z
---

# Team Wisdom

Reusable patterns and heuristics learned through work. NOT transcripts — each entry is a distilled, actionable insight.

## Patterns

<!-- Append entries below. Format: **Pattern:** description. **Context:** when it applies. -->

**Pattern:** Verify every Sentinel table name against the Azure-Sentinel repo `CustomTables/` schemas and actual connector definitions before writing KQL. Table names in proposals are frequently wrong (`_CL` suffix on native tables, speculative resource-specific names). **Context:** Any time a report proposes KQL queries or references Sentinel tables.

**Pattern:** Check the `Solutions/README.md` certification FAQ for hard rejection criteria (missing ReleaseNotes.md, wrong branding, missing GUID) before beginning solution authoring. These are binary pass/fail gates. **Context:** Before any Sentinel solution content is authored or reviewed.

**Pattern:** When multiple team artifacts reference the same platform entity (table, API, connector), cross-check for internal consistency before presenting to stakeholders. Disagreement on table names signals insufficient evidence. **Context:** Multi-agent discovery phases where different agents research overlapping domains.
