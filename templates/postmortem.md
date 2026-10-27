# Postmortem: `[short incident title]`

> This postmortem is blameless. Its purpose is to understand how our systems and processes allowed the incident to happen, not to find who was at fault. The people involved describe what they knew and decided at the time; decisions that were reasonable with the information available then are not judged with hindsight.

| | |
|---|---|
| Incident date | `[...]` |
| Severity | `[Sev1 / Sev2 / Sev3]` |
| Status | `[draft / in review / final]` |
| Author | `[...]` |
| Incident commander | `[...]` |
| Reviewers | `[...]` |

## Summary

`[Three to five sentences: what happened, who was affected, for how long, what the main cause was, and how service was restored.]`

## Impact

| Measure | Value |
|---|---|
| Impact started | `[time WIB]` |
| Detected | `[time WIB]` (time since start: `[minutes]`) |
| Recovered | `[time WIB]` (outage duration: `[minutes]`) |
| Users or transactions affected | `[number or percentage]` |
| Error budget used | `[percent of the 30-day budget]` for the `[...]` SLO |
| Business impact | `[revenue, compensation, complaints, reputation]` |

## Timeline

All times in WIB (UTC+7). Include the signals visible at the time (alerts, graphs, user reports) and the decisions taken.

| Time | Event |
|---|---|
| `[hh:mm]` | `[change or trigger]` |
| `[hh:mm]` | `[alert fired / first report received]` |
| `[hh:mm]` | `[incident commander assigned, severity set]` |
| `[hh:mm]` | `[diagnosis steps and findings]` |
| `[hh:mm]` | `[recovery steps]` |
| `[hh:mm]` | `[recovered, monitoring started]` |
| `[hh:mm]` | `[incident declared over]` |

## Causes and contributing factors

**Trigger.** `[The event that started the incident, for example a release, a traffic surge or a partner outage.]`

**Root cause.** `[Why the trigger could cause this much impact. Ask "why" several times until you reach a condition of the system or the process.]`

**Contributing factors.** `[Things that made the impact larger or the recovery slower: no timeouts, late alerts, an outdated runbook, slow emergency access, and so on.]`

## Detection and response

- How was the incident discovered? `[SLO alert / user report / by chance]`
- Did the right alert fire at the right time? `[...]`
- Was a runbook available, and could it be followed? `[...]`
- What slowed down recovery? `[...]`

## What went well, what did not, and where we got lucky

| Went well | Did not go well | Where we got lucky |
|---|---|---|
| `[...]` | `[...]` | `[...]` |

## Action items

Every action item has an owner, a due date and a ticket. Favor actions that prevent a recurrence or speed up detection over "be more careful".

| Action | Type | Priority | Owner | Due date | Ticket |
|---|---|---|---|---|---|
| `[...]` | `[prevent / detect / mitigate / process]` | `[high / medium / low]` | `[...]` | `[...]` | `[...]` |

## Lessons learned

`[What other teams should know. A widely shared postmortem keeps other teams from having the same incident.]`

---

Writing tips:
- Write the draft within 5 business days while memories are fresh; the timeline can be taken from the coordination channel and the scribe's notes.
- A review meeting of 30–60 minutes is enough. Focus on the action items, not on the timeline.
- Track the completion of action items every month; a postmortem without completed actions simply becomes an archive.
