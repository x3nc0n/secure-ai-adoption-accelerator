# AIGS-Notify-001-TeamsAlert

**Playbook ID:** PB-NOTIFY-01
**Type:** Notification
**Solution:** Microsoft Sentinel — AI Governance Solution
**Version:** 0.1.0-preview.1
**Author:** x3nc0n

---

## Overview

AIGS-Notify-001-TeamsAlert delivers a structured Teams notification when any AI Governance Solution analytic rule fires. It posts an adaptive card to a configured SOC Teams channel with incident context drawn from the triggering Sentinel incident. This playbook is **notification-only** — it does not perform any approval, configuration change, or remediation.

---

## Trigger

| Attribute | Value |
|-----------|-------|
| **Trigger type** | Microsoft Sentinel — When Azure Sentinel incident creation rule is triggered |
| **Scope** | Any AIGS analytic rule incident (all modules) |
| **Attachment** | Sentinel incident details passed as trigger body (incident ID, title, severity, description, entities, URL) |

---

## Teams Connector Architecture

> ⚠️ **This playbook uses the Microsoft Teams connector with an OAuth connection — not an incoming webhook URL.**

| Component | Configuration | Purpose |
|-----------|---------------|---------|
| Teams connection | OAuth — delegated account | Enables rich adaptive card delivery; non-functional via incoming webhook |
| Card delivery | "Post an adaptive card to a Teams channel" action | One-directional notification; no interactive buttons |

The adaptive card displays incident title, severity badge, incident ID, description, and direct Sentinel URL. The OAuth connection must be authorized post-deployment using a delegated service account or licensed Teams user account.

---

## Actions

| Step | Action | Notes |
|------|--------|-------|
| 1 | Parse incident trigger body | Extract: incident ID, title, severity, incident URL |
| 2 | Build adaptive card payload | Populate card with incident title, severity, incident ID, Sentinel URL link |
| 3 | Post adaptive card to Teams channel | Teams connector: "Post an adaptive card to a Teams channel" with groupId and channelId parameters |
| 4 | Add comment to incident | Write: "🔔 **PB-NOTIFY-01**: AI Governance Teams alert delivered to configured SOC channel at [timestamp]. Incident ID: [id]. Awaiting SOC triage." |
| 5a (Success) | Conclude | No further action; incident remains in SOC channel |
| 5b (Failure) | Handle failure | Write failure message to incident comment |

---

## Identity and Permissions

| Attribute | Value |
|-----------|-------|
| **Identity type** | User-Assigned Managed Identity (UAMI) |
| **UAMI role** | `Microsoft Sentinel Reader` (built-in role `ab8e14d6-4a74-4a29-9ba8-549422addade`) |
| **UAMI scope** | Sentinel workspace resource ID only |
| **Teams connection** | OAuth — delegated connection (separate from UAMI; requires service/operator account authorization post-deployment) |

The UAMI provides read-only access to Sentinel incidents only. It cannot modify incidents, analytics rules, automation rules, or any other Azure resource. The Teams OAuth connection is independent of the UAMI and must be authorized as a separate step.

---

## Deployment State

| Attribute | Value |
|-----------|-------|
| **Deployed state** | `Enabled` |
| **Prerequisites met** | Teams OAuth connection must be authorized in Azure Portal before first execution |

The Logic App deploys in `Enabled` state. If the Teams OAuth connection is not authorized at deployment, the first execution will fail. Authorization is performed in the Azure Portal: navigate to the Logic App → **API connections** → **teams-AIGS-Notify-001-TeamsAlert** → **Edit API connection** → **Authorize** with a delegated account.

---

## Failure Behavior

| Failure Condition | Behavior |
|------------------|---------|
| Teams card delivery fails (network, auth) | Write error to incident comment: "❌ **PB-NOTIFY-01 FAILURE**: Teams notification failed at [timestamp]. Check Logic App run history and verify Teams connection authorization. Manual SOC notification required." |
| Incident details unavailable or malformed | Write error to incident comment with details; log to Logic App diagnostics (`AzureDiagnostics`) |
| UAMI authentication fails | Logic App enters failed run state; write error to incident comment and `AzureDiagnostics`; no silent failure |
| Teams channel not found or bot not present | Write error to incident comment and log to diagnostics |

All failures produce durable incident comments (retained per workspace retention policy) and Logic App run history. No failures are silent.

---

## Rollback

**Not applicable.** This playbook performs no configuration changes and makes no modifications to Azure resources, Sentinel rules, Sentinel automation rules, or incident status. The Teams channel post is informational-only; the incident comment provides a permanent audit record.

---

## Parameters

Deployment accepts the following parameters (provided at template deployment time):

| Parameter | Type | Required | Notes |
|-----------|------|----------|-------|
| `playbookName` | string | No | Name of the Logic App resource; default: `AIGS-Notify-001-TeamsAlert` |
| `location` | string | No | Azure region; default: resource group location |
| `uamiResourceId` | string | ✅ Yes | Resource ID of the User-Assigned Managed Identity. Format: `/subscriptions/{subscriptionId}/resourceGroups/{resourceGroup}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/{identityName}` |
| `teamsGroupId` | string | ✅ Yes | Microsoft Teams group (team) object ID for the notification destination |
| `teamsChannelId` | string | ✅ Yes | Microsoft Teams channel ID within the group for the notification destination |

---

## Post-Deployment Manual Wiring

The playbook does **not** automatically attach to analytic rules. Manual wiring is required:

1. **Identify target AIGS analytic rules** in Microsoft Sentinel — All AIGS rules (e.g., AIGS-CD-001, AIGS-Auth-001, etc.)

2. **Create automation rules** that trigger this playbook:
   - Rule condition: `Incident status is Created` (or updated as needed)
   - Triggered rules: Select the target analytic rule(s)
   - Run playbook action: Select `AIGS-Notify-001-TeamsAlert`
   - Example: Automation Rule Name = `AIGS-Auto-Notify-OnIncident`

This is a **manual process** — the deployment template does **not** include automation rules. Each deployment must configure automation rules separately.

---

## Deployment Notes

- This playbook deploys as a Logic App (Consumption plan). Cost is per-execution only; no always-on cost.
- Logic App diagnostic settings are enabled by default, sending run history to the Sentinel workspace (`AzureDiagnostics`).
- The Teams OAuth connection deploys as a separate resource and must be authorized post-deployment before any notification can be sent.
- If the Teams connection is not authorized, the playbook will remain enabled but will fail on first execution.

---

## Related Playbooks

| Playbook | Relationship |
|----------|-------------|
| AIGS-Auto-001-RestoreDiagnostics | Approval-gated auto-remediation; fires for CD005 incidents only (approval + remediation) |
