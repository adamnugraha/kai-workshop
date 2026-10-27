# Error budget policy: `[service name]`

| | |
|---|---|
| Version | `[1.0]` |
| Effective from | `[date]` |
| Document owner | `[name, title]` |
| Review | Every quarter, or after a Sev1 incident |

## 1. Purpose

This policy sets out what the team does when the reliability of `[service name]` starts to let users down. It is agreed in advance so that a decision to delay features no longer feels like a personal choice by the IT team, and so that reliability is treated as a feature with a target and a budget.

## 2. SLOs covered

| SLO | Target | Window | Error budget | Dashboard |
|---|---|---|---|---|
| `[Booking availability]` | `[99.9%]` | Rolling 30 days | `[43 minutes / 0.1% of requests]` | `[link]` |
| `[Booking latency under 500 ms]` | `[99%]` | Rolling 30 days | `[1% of requests]` | `[link]` |
| `[E-ticket issuance]` | `[99.9%]` | Rolling 30 days | `[0.1% of payment attempts]` | `[link]` |

The error budget is calculated from measured data, not from manual reports. If the measurement itself breaks, time without data counts as `[consumed / not counted]` (choose one and record it here).

## 3. Rules by remaining error budget

| Error budget remaining | Release rules | Team focus | Who approves exceptions |
|---|---|---|---|
| Above 50% | Normal releases on schedule | New features | Team lead |
| 25% to 50% | Releases must go through a canary or gradual rollout; major releases need approval | Balance features and reliability work | `[Head of development]` |
| Below 25% | Only bug fixes, reliability improvements and emergency releases | Reliability work | `[Head of IT]` |
| Exhausted | Freeze feature releases until the SLO has been back on target for `[7 days]` in a row | Postmortem and follow-up | `[Head of IT together with the business owner]` |

Always allowed, whatever the remaining budget: security fixes, changes that improve reliability, and changes required by regulation.

## 4. Obligations when the budget runs low

- Any single incident that uses more than **20%** of the error budget in one window requires a postmortem, whatever its severity.
- High-priority postmortem actions go into the next sprint, ahead of new features.
- If the budget is exhausted in two consecutive windows, the team and the business owner review whether the target is too high or the architecture needs to change.

## 5. Outages caused by others

Outages caused by third parties (for example, a payment partner) or by other internal services **still count**, because users still feel them. If one party repeatedly consumes most of the budget, the follow-up is a design change (timeouts, circuit breakers, queues, a backup provider) or a contract discussion, not an exclusion from the calculation.

## 6. Escalation

If there is disagreement about how this policy applies, `[Head of IT]` and `[business owner]` decide within `[2 business days]`. The decision and its rationale are recorded at `[link]`.

## 7. Review

The policy is reviewed every quarter by looking at how often each rule tier was triggered, whether the rules were followed, and whether users noticed an improvement.

## 8. Approval

| Role | Name | Date | Signature |
|---|---|---|---|
| Business owner | `[...]` | `[...]` | |
| Head of application development | `[...]` | `[...]` | |
| Head of IT operations / SRE | `[...]` | `[...]` | |
