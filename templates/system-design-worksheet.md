# System design worksheet

One worksheet per system, or per most important user journey. Fill it in before building a new system, before modernizing a legacy one, and at every architecture review. The example column uses the fictional RelNusa application from the lab; replace it with your own system.

The order runs deliberately from targets to technology: the technology stack is chosen last, once the targets, the math and the risks are clear.

## 1. User journeys and targets

| Journey | Availability target | Latency target | Can it be delayed? | Owner | Example (RelNusa) |
|---|---|---|---|---|---|
| `[...]` | `[...]` | `[...]` | `[...]` | `[...]` | Search schedules: 99.9%, 99% under 500 ms, cannot be delayed |
| `[...]` | `[...]` | `[...]` | `[...]` | `[...]` | Book a seat: 99.9%, no server errors |
| `[...]` | `[...]` | `[...]` | `[...]` | `[...]` | E-ticket issued: 99.9% within two minutes, can go through a queue |
| `[...]` | `[...]` | `[...]` | `[...]` | `[...]` | Internal reports: 99%, can be delayed |

Allowed downtime per month: 99% = 7 hours 18 minutes, 99.5% = 3 hours 39 minutes, 99.9% = 43 minutes 50 seconds, 99.95% = 21 minutes 55 seconds, 99.99% = 4 minutes 23 seconds. Planned maintenance counts too.

## 2. Availability chain

List every component that **must** work for the main journey to succeed.

| Component on the critical path | Availability on its own | Number of copies that do not fail together | Availability with redundancy | Can it be taken off the critical path? |
|---|---|---|---|---|
| `[...]` | `[...]` | `[...]` | `[...]` | `[...]` |
| `[...]` | `[...]` | `[...]` | `[...]` | `[...]` |
| `[...]` | `[...]` | `[...]` | `[...]` | `[...]` |

Formulas:
- Chain: multiply all critical components. Five components at 99.9% give 0.999⁵ = **99.50%**.
- Redundancy: a component with availability *a* and *n* copies that do not fail together gives 1 − (1 − *a*)ⁿ. Two copies at 99% give **99.99%**.
- A component taken off the critical path (for example, payment through a queue) drops out of the multiplication, but still needs its own SLO.

| Result | Value |
|---|---|
| Current chain | `[...]` |
| Chain after design improvements | `[...]` |
| Journey target | `[...]` |

## 3. Failure domains

| Domain | Example causes | What users experience when it fails | Where the redundancy is | Last tested |
|---|---|---|---|---|
| Process | Application hangs, runs out of memory | `[...]` | `[automatic restarts, multiple replicas]` | `[...]` |
| Server or node | Hardware failure | `[...]` | `[replicas on different nodes]` | `[...]` |
| Zone or server room | Power, cooling, core switch | `[...]` | `[replicas and database in different zones]` | `[...]` |
| Data center or region | Disaster, loss of intercity links | `[...]` | `[second site and data replication]` | `[...]` |

| Disaster recovery | Target | Last test result |
|---|---|---|
| Recovery time (RTO) | `[...]` | `[...]` |
| Acceptable data loss (RPO) | `[...]` | `[...]` |

For a 99.9% target, design at least to the zone level.

## 4. The busiest minute

| Item | Value | Example calculation (invented figures) |
|---|---|---|
| Prospective users at the peak | `[...]` | 300,000 in the first 10 minutes of sales |
| Requests per user | `[...]` | 15: search, choose a seat, book, pay, check status |
| Average requests per second | `[...]` | 300,000 × 15 ÷ 600 seconds = 7,500 |
| First-minute factor | `[...]` | 3 times the average = 22,500 per second |
| Share of the read path | `[...]` | About 90%, served by caches and read replicas |
| Tested capacity of the write path | `[...]` | `[buyers per second admitted by the waiting room]` |
| Capacity headroom | `[...]` | 1.5 to 2 times the peak |
| What happens above capacity | `[...]` | A waiting room with a queue number, not an error |
| Last load test | `[date, load, result]` | `[...]` |

## 5. Data and consistency

| Data | Must be exact, can lag, or can follow later | Stored in | How it is protected |
|---|---|---|---|
| `[...]` | `[...]` | `[...]` | `[...]` |
| Example: remaining seats | Must be exact | Primary database | Short transactions, idempotency keys |
| Example: schedules | Can lag a few seconds | Cache and read replicas | Short cache lifetimes |
| Example: payments and e-tickets | Can follow later | Queue | Retries with backoff, reconciliation with the bank |

## 6. Dependencies

| Dependency | Timeout | Retry | Circuit breaker | What do users see when it is down or slow? |
|---|---|---|---|---|
| `[...]` | `[...]` | `[...]` | `[yes / no]` | `[...]` |
| Example: bank | 800 ms | Retried from the queue | Yes | A "waiting for payment" status; the seat stays locked |

## 7. Technology stack

| Layer | Choice | Rationale | Who operates it | Example (RelNusa) |
|---|---|---|---|---|
| Edge and entry point | `[...]` | `[...]` | `[...]` | Traefik, with the waiting room in the gateway |
| Platform | `[...]` | `[...]` | `[...]` | Kubernetes (k3s), three zones |
| Transactional database | `[...]` | `[...]` | `[...]` | PostgreSQL with CloudNativePG, one primary and two replicas |
| Cache and queue | `[...]` | `[...]` | `[...]` | Redis and Redis Streams |
| Observability | `[...]` | `[...]` | `[...]` | Prometheus, Grafana, Jaeger, OpenTelemetry |
| Progressive delivery | `[...]` | `[...]` | `[...]` | Argo Rollouts with Prometheus analysis |
| Load and chaos testing | `[...]` | `[...]` | `[...]` | k6 and Chaos Mesh |

Choose what your team can operate. Managed services shift part of the operational work to the provider, but accountability for availability stays with the system owner.

## 8. Releases and changes

| Question | Yes / No | Notes |
|---|---|---|
| Rolling updates with readiness probes and graceful shutdown? | | |
| Canary releases with automated checks and automatic rollback? | | |
| Incremental database schema changes (expand and contract)? | | |
| Feature flags for risky features? | | |
| Can a release be rolled back in under five minutes? | | |
| No maintenance windows that stop the service? | | |

## 9. Observability

| Item | Details |
|---|---|
| Where the SLIs are measured | `[front door: load balancer or ingress]` |
| Traces from the front door to the database and partners | `[yes / not yet]` |
| User journey dashboard | `[link]` |
| Burn-rate alerts | `[link; derive them from the SLO worksheet]` |
| A runbook for every paging alert | `[link]` |

## 10. Ten design review questions

| No | Question | Answer | Follow-up |
|---|---|---|---|
| 1 | Which passenger journey matters most, and what is its target? | | |
| 2 | Where is the single point of failure? | | |
| 3 | What happens if one zone goes down? | | |
| 4 | What is the load in the busiest minute, and what happens above it? | | |
| 5 | Which components truly must be on the purchase path? | | |
| 6 | What happens if a partner slows down by three seconds? | | |
| 7 | Which data must be exact, and which can lag? | | |
| 8 | Can we release and migrate without taking the service down? | | |
| 9 | How do we know passengers are failing before they tell us? | | |
| 10 | When was the recovery plan last actually tested? | | |

## 11. Decision log

Record every important design decision, so that the reasoning is not lost when the team changes.

| Date | Decision | Alternatives rejected | Rationale | Review |
|---|---|---|---|---|
| `[...]` | `[...]` | `[...]` | `[...]` | `[...]` |
| Example | Payments are processed through a queue | Calling the bank inside the booking transaction | A slow bank must not hold seat locks and database connections | Every quarter |

Fields to fill in are marked `[...]`. Example figures are for illustration only.
