# SLO worksheet

One worksheet per user journey. Fill it in from top to bottom; each section builds on the one before it.

## 1. User journey

| Item | Details | Example (RelNusa) |
|---|---|---|
| Journey name | `[...]` | Book and pay for a ticket |
| Who the users are | `[...]` | Passengers on the app and the website |
| What "success" means to the user | `[...]` | The seat is locked and the e-ticket is issued |
| Business owner | `[...]` | Head of ticket sales product |
| Technical owner | `[...]` | Booking platform team |
| Services involved | `[...]` | Gateway, booking, payment worker, bank |
| Most critical times | `[...]` | Ticket sales opening for the holiday season |

## 2. SLIs: what to measure

An SLI is always **good events ÷ all events**, measured as close to the user as possible.

| SLI | Good events | All events | Measured at | Example query |
|---|---|---|---|---|
| Availability | Requests without a server error (not 5xx) | All requests | Load balancer or ingress | `sum(rate(traefik_router_requests_total{code!~"5.."}[5m])) / sum(rate(traefik_router_requests_total[5m]))` |
| Latency | Requests completed under `[500 ms]` | All requests | Load balancer or ingress | the `le="0.5"` histogram bucket divided by the request count |
| Journey completion | `[Payment succeeded, e-ticket issued]` | `[All payment attempts]` | The service that completes the journey | `payment_attempts_total{outcome="success"}` divided by all attempts |
| `[...]` | `[...]` | `[...]` | `[...]` | `[...]` |

Check questions:
- Does this SLI drop when users are actually affected? Test it against data from past incidents.
- Does this SLI stay quiet when users are not affected (for example, high CPU while every request is fast)?
- What does it **not** catch? Example: if the payment workers are down, there are no payment attempts, so the completion SLI does not move. Monitor the queue age for that case as well.

## 3. Current data

Measure for at least four weeks before setting a target.

| SLI | Week 1 | Week 2 | Week 3 | Week 4 | Worst |
|---|---|---|---|---|---|
| `[...]` | `[...]` | `[...]` | `[...]` | `[...]` | `[...]` |

## 4. SLOs: the targets

Rule of thumb: set the target slightly below the worst performance users still find acceptable, not as high as possible. Each additional nine usually requires architectural change, not just working harder.

| SLI | Target | Window | Error budget per window |
|---|---|---|---|
| `[...]` | `[99.9%]` | Rolling 30 days | `[43 minutes, or 1 in every 1,000 requests]` |

### Reference table: targets and allowed failure

| Target | Allowance per 30 days (time) | Allowance per 1 million requests |
|---|---|---|
| 99% | 7 hours 12 minutes | 10,000 requests |
| 99.5% | 3 hours 36 minutes | 5,000 requests |
| 99.9% | 43 minutes 12 seconds | 1,000 requests |
| 99.95% | 21 minutes 36 seconds | 500 requests |
| 99.99% | 4 minutes 19 seconds | 100 requests |

Formulas: time allowance = (1 − target) × 43,200 minutes. Request allowance = (1 − target) × the number of requests in the window.

## 5. Burn-rate alerts

Burn rate = current error rate ÷ allowed error rate. A burn rate of 1 means the budget runs out exactly at the end of the 30-day window.

| Type | Burn rate | Long window | Short window | Budget used when it fires | Budget gone in | Sent to |
|---|---|---|---|---|---|---|
| Page | 14.4 | 1 hour | 5 minutes | 2% | about 2 days | On-call, immediately |
| Page | 6 | 6 hours | 30 minutes | 5% | 5 days | On-call, immediately |
| Ticket | 3 | 1 day | 2 hours | 10% | 10 days | Team queue, business hours |
| Ticket | 1 | 3 days | 6 hours | 10% | 30 days | Team queue, business hours |

An alert fires when **both** windows exceed the threshold. For a 99.9% SLO and a burn rate of 14.4, the error threshold is 14.4 × 0.1% = 1.44% of requests failing. Source: Google, *The Site Reliability Workbook*, chapter 5. Tools such as [Sloth](https://sloth.dev) generate these Prometheus rules automatically from an SLO definition; see the example in `k8s/slo/relnusa-slos.yaml`.

## 6. Agreement

| Item | Details |
|---|---|
| Error budget policy that applies | `[link]` |
| SLO dashboard | `[link]` |
| A runbook for every paging alert | `[link]` |
| SLO review schedule | `[monthly, with the business owner]` |
| Approved by (business) | `[name, date]` |
| Approved by (IT) | `[name, date]` |
