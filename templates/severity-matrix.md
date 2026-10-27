# Severity matrix and incident roles

Severity levels are agreed in advance so that they are not debated in a moment of panic. When in doubt between two levels, choose the higher one; lowering a severity is easier than raising it too late.

## Severity levels

| Level | Definition | Examples | Response target | Who is called | Updates to management | Postmortem |
|---|---|---|---|---|---|---|
| **Sev1** | The main journey has stopped for many users, or there is a risk to data, security or safety | Ticket sales have stopped; payments are failing at scale; customer data has leaked | 5 minutes | On-call, incident commander, service owner | Every 30 minutes | Required, draft within 5 business days |
| **Sev2** | One function is partly degraded, or the main journey is much slower | Search is very slow; one payment method is failing; e-tickets are delayed | 15 minutes | On-call, service owner | Every 30 minutes | Required |
| **Sev3** | A minor issue with a workaround available to users | The trip history feature returns errors; notifications are late | Same business day | Service owner team | Not needed | If it recurs |
| `[Sev4]` | `[Optional: cosmetic or informational issues]` | `[...]` | `[...]` | `[...]` | `[...]` | `[...]` |

Replace the examples with your actual user journeys. For a transport organization, also consider the impact on field operations (for example, staff unable to check tickets).

## Roles during Sev1 and Sev2 incidents

| Role | Responsibilities | Deliberately does not |
|---|---|---|
| **Incident commander (IC)** | Leads, sets priorities, makes decisions, sets and changes the severity, declares the incident over | Type the fix commands |
| **Operations** | Diagnoses and restores service; reports findings to the IC | Answer management questions directly |
| **Communications** | Gives regular updates to management, customer service and other stakeholders | Change the system |
| **Scribe** | Records the timeline, the decisions and who did what, with timestamps | |

In a small incident one person can hold more than one role, but the IC and operations should still be different people.

## Coordination rules

- One coordination channel per incident: `[#incident-date-name]` or `[group/bridge]`.
- Important decisions are stated by the IC and recorded by the scribe.
- Restore first, find the cause later. Rolling back the last release is a legitimate first step if the incident started after a change.
- The IC declares the incident over once the SLIs have been back to normal for at least `[15 minutes]`.

## Status update template

```
[Sev1/Sev2] [short title] · update [n] · [time WIB]
Current impact : [who is affected, and how much]
Started        : [time WIB]
Status         : [investigating / cause identified / recovery in progress / recovered, monitoring]
Next steps     : [what is being worked on]
Next update    : [time WIB]
IC             : [name]
```

## Approval

| Role | Name | Date |
|---|---|---|
| Head of IT | `[...]` | `[...]` |
| Business owner | `[...]` | `[...]` |
