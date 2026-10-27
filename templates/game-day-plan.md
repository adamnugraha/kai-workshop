# Game day plan

A game day is a planned failure drill: the team injects a failure on purpose to test the architecture, the alerts, the dashboards, the runbooks and the way the team coordinates. Start in staging; move to production only once the team is used to it, and with strict safety limits.

## Template

| Item | Details |
|---|---|
| Drill name | `[...]` |
| Date and time | `[...]` |
| Environment | `[staging / limited production]` |
| Facilitator | `[the person who injects the failure]` |
| Team being trained | `[on-call and the service team]` |
| Observers and scribe | `[...]` |

### 1. Hypothesis

One sentence that can be proven right or wrong: "If `[failure]`, then `[expected system behavior]` and `[expected alert or response]` within `[time]`."

### 2. Steady state

| Measure | Normal value | Source |
|---|---|---|
| `[Main SLI]` | `[...]` | `[dashboard]` |
| `[...]` | `[...]` | `[...]` |

### 3. Failure

| Item | Details |
|---|---|
| Type of failure | `[slow network / pod killed / node down / dependency errors / database failover]` |
| Tool | `[Chaos Mesh / script / manual]` |
| Scope | `[service, percentage of pods, zone]` |
| Maximum duration | `[minutes]` |

### 4. Safety limits and stop button

- Stop immediately if: `[for example, the user SLI is below 95% for more than 2 minutes; errors appear in services outside the scope]`.
- How to stop: `[command or button, and who presses it]`.
- Notify in advance: `[customer service, other teams that depend on the service]`.

### 5. Observations

| Question | Result |
|---|---|
| Did the system behave as the hypothesis predicted? | `[...]` |
| Did the right alert fire, and when? | `[...]` |
| Did the dashboards show the cause clearly? | `[...]` |
| Could the runbook be followed without help? | `[...]` |
| Did the system recover by itself once the failure was stopped? | `[...]` |
| How much error budget was used? | `[...]` |

### 6. Timeline

| Time | Event |
|---|---|
| `[T+0:00]` | `[failure starts]` |
| `[...]` | `[...]` |

### 7. Findings and action items

| Finding | Action | Owner | Due date |
|---|---|---|---|
| `[...]` | `[...]` | `[...]` | `[...]` |

Write the drill postmortem with the same postmortem template as a real incident.

---

## Filled-in example: the bank slows down (demo 4 in the lab)

| Item | Details |
|---|---|
| Hypothesis | If the bank takes 3 seconds to answer, booking keeps working and the ticket issuance page alert reaches Telegram within 3 minutes |
| Steady state | Modern site availability 100%; payments succeed almost 100% of the time; circuit breaker closed |
| Failure | 3 seconds of network delay to the simulated bank through Chaos Mesh (`./lab.sh chaos bank-slow`), or the simulated bank's slow mode (`./lab.sh bank slow`) |
| Maximum duration | 3 minutes |
| Stop button | `./lab.sh chaos stop` or `./lab.sh bank normal` |
| Observations | The circuit breaker opens; seats stay locked; the availability SLO stays green; the ticket issuance burn rate goes above 14.4; the alert reaches Telegram; traces show bank calls timing out at 800 ms; after the failure stops, the payment queue drains with no double charges |
| Result in the lab | The circuit breaker opened about 20 seconds after the failure started; the page alert arrived after about 1 minute 20 seconds; the modern site showed no errors; once the bank recovered, 190 pending payments cleared within 20 seconds with no double charges |
| A common finding | The recovery message in Telegram only arrives about 30 minutes after the failure stops, because a 3-minute total outage also triggers the 6-hour and 30-minute window pair. This is by design, and the team should know it so that the alert is not mistaken for a stuck one |
