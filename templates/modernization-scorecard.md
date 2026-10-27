# Modernization scorecard

This scorecard helps you choose the **first function** to separate from a legacy system. Modernization does not have to happen all at once: start with the function that is most critical to users and most often the source of outages, then move functions one at a time with the strangler fig pattern.

## 1. Function inventory

Fill in one row per business function (not per server). Score 1 = good, 3 = poor. The highest total is the first candidate.

| Function | Impact on users when it fails | Outage frequency, last 12 months | Load at peak | Unprotected external dependencies | Difficulty of releases | Total |
|---|---|---|---|---|---|---|
| `[Booking and payment]` | `[3]` | `[3]` | `[3]` | `[3]` | `[2]` | `[14]` |
| `[Schedule search]` | `[...]` | `[...]` | `[...]` | `[...]` | `[...]` | `[...]` |
| `[...]` | `[...]` | `[...]` | `[...]` | `[...]` | `[...]` | `[...]` |

## 2. Application checklist

Answer for the candidate application or function. Every "no" is an upper limit on availability that has to be fixed through architecture, not through working harder.

| Area | Question | Yes / No | Notes |
|---|---|---|---|
| Single point of failure | Does the application keep serving if one server or one zone goes down? | | |
| Database | Is there a replica with automatic failover, and has it been tested? | | |
| Releases | Can releases be done without stopping the service? | | |
| Releases | Can a release be rolled back in under 5 minutes? | | |
| Releases | Are there progressive (canary) releases with automated checks? | | |
| Surges | Is there a queue or waiting room for requests above capacity? | | |
| Surges | Is frequently read data served from a cache? | | |
| Surges | Can capacity be added automatically? | | |
| Dependencies | Does every call to another system have a timeout? | | |
| Dependencies | Is there a circuit breaker for external partners? | | |
| Dependencies | Is work that does not have to be immediate processed through a queue? | | |
| Data | Are transactions short (no locks held while calling other systems)? | | |
| Data | Are there idempotency keys for payments and other repeatable requests? | | |
| Observability | Are the SLIs measured from the user's side? | | |
| Observability | Are there traces from the front door to the database and partners? | | |
| Operations | Is there a runbook for the most frequent failures? | | |

## 3. First slice plan

| Item | Details |
|---|---|
| Function to separate | `[...]` |
| Why it was chosen | `[highest score, business impact, outage data]` |
| Traffic routing pattern | `[API gateway / ingress / feature flag]` |
| Data: split or copied | `[...]` |
| SLO from day one | `[link to the SLO worksheet]` |
| How to switch back to the legacy system if it fails | `[...]` |
| Success measures | `[for example, errors during surges drop from X% to Y%; release time drops from hours to minutes]` |
| Target date | `[...]` |
