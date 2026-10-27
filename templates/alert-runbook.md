# Alert runbook

One runbook per alert. Write it so that an on-call engineer who sees this alert for the first time, at three in the morning, still knows the first step. Link the runbook from the alert's annotations.

## Template

### `[AlertName]`

| | |
|---|---|
| Severity | `[page / ticket]` |
| SLO | `[SLO name, target]` |
| Owner | `[team]` |
| Last tested | `[date of the game day or incident]` |

**What it means.** `[One sentence: what users experience when this alert fires.]`

**Impact.** `[Who is affected, what they cannot do, an initial estimate of the severity.]`

**Look first.**
1. `[SLO dashboard: link]`
2. `[Service dashboard: link]`
3. `[Traces: link with the service filter]`
4. `[Logs: saved query]`

**Diagnosis.**

| If you see | Likely cause | Step |
|---|---|---|
| `[...]` | `[...]` | `[...]` |

**Recovery.**
1. `[The safest and fastest step first, for example rolling back the last release]`
2. `[...]`

**Escalation.** `[Who, and when, for example: if not recovered within 30 minutes, call ...]`

**Done when.** `[The SLI has been back to normal for at least 15 minutes; the queue is empty; and so on.]`

---

## Filled-in example: `RelnusaModernTicketIssuance`

| | |
|---|---|
| Severity | page (burn rate 14.4 over 1 hour and 5 minutes, or 6 over 6 hours and 30 minutes) |
| SLO | Ticket issuance, 99.9% of payment attempts succeed, 30 days |
| Owner | Booking platform team |
| Last tested | Game day, demo 4 in the lab |

**What it means.** Payments to the bank are failing or timing out far more often than normal, so passengers already hold a seat but have not received their e-ticket. The site can still be fast and error-free.

**Impact.** Passengers are waiting for their e-tickets; seats stay locked for the hold period (10 minutes in the lab). If it lasts longer than the hold period, seats can be released and passengers have to book again. Initial severity: Sev2, raised to Sev1 if almost all payments fail for more than 10 minutes.

**Look first.**
1. Grafana `RelNusa · 2 · SLOs and error budgets`: the ticket issuance and availability burn rates. If availability stays green, the problem is in the payment path, not in the site.
2. Grafana `RelNusa · 3 · Inside the modern architecture`, the *Payments and the bank* row: the circuit breaker, payment attempts by outcome, and the queue.
3. Jaeger, service `payment-worker`: find traces with errors and look at the bank call spans.

**Diagnosis.**

| If you see | Likely cause | Step |
|---|---|---|
| The `timeout` outcome dominates and the breaker is open | The bank is slow | Check the payment partner's status; contact the bank's technical contact |
| The `failure` outcome dominates | The bank is rejecting requests or returning errors | Check the error codes in the worker logs; check credentials and certificates |
| The `error` outcome dominates | A database or Redis problem | Check the database panels and active connections |
| The queue grows but there are no payment attempts | Workers are down or stuck | `kubectl -n modern get pods -l app=payment-worker`; check the logs |

**Recovery.**
1. Do not raise the timeout or switch off the circuit breaker; both protect the whole system.
2. If the bank is slow: wait, or switch to a backup provider if one exists. Pending payments stay in the queue and are paid automatically when the bank recovers, with no double charges thanks to idempotency keys.
3. If the problem started after a release: roll back the worker release.
4. If the workers are down: check the pod events and node resources, then restart them.

**Escalation.** If not recovered within 30 minutes, or if the seat hold period is about to run out, raise it to Sev1 and inform customer service.

**Done when.** The circuit breaker is closed, the payment queue is empty, and the 5-minute burn rate has been back below 1 for at least 15 minutes.
