# 90-day plan: getting started with SRE

This plan is deliberately small: one or two user journeys, taken all the way through, then expanded. Adjust the owners and dates.

## Days 1–30 · Measure

| | Activity | Owner | Date | Done |
|---|---|---|---|---|
| 1 | Choose the 1–2 most critical user journeys and assign a business owner and a technical owner | `[...]` | `[...]` | [ ] |
| 2 | Set up SLI measurement at the front door (load balancer, ingress or API gateway) | `[...]` | `[...]` | [ ] |
| 3 | Build one simple SLI dashboard that everyone can open | `[...]` | `[...]` | [ ] |
| 4 | Agree on the severity matrix, incident roles and escalation paths | `[...]` | `[...]` | [ ] |
| 5 | Start using the postmortem template for every Sev1 and Sev2 incident | `[...]` | `[...]` | [ ] |

## Days 31–60 · Agree

| | Activity | Owner | Date | Done |
|---|---|---|---|---|
| 6 | Set SLOs from four weeks of data (SLO worksheet) | `[...]` | `[...]` | [ ] |
| 7 | Sign the error budget policy with the business owner | `[...]` | `[...]` | [ ] |
| 8 | Replace CPU- and memory-based paging alerts with SLO burn-rate alerts | `[...]` | `[...]` | [ ] |
| 9 | Write runbooks for the five most frequent alerts | `[...]` | `[...]` | [ ] |
| 10 | Add OpenTelemetry to the most critical services, all the way to the database and partners | `[...]` | `[...]` | [ ] |

## Days 61–90 · Practice

| | Activity | Owner | Date | Done |
|---|---|---|---|---|
| 11 | First game day in staging, using the game day plan | `[...]` | `[...]` | [ ] |
| 12 | Canary releases with automated analysis for one service | `[...]` | `[...]` | [ ] |
| 13 | First strangler fig slice on the same user journey (modernization scorecard) | `[...]` | `[...]` | [ ] |
| 14 | First monthly SLO review with the business owner | `[...]` | `[...]` | [ ] |

## Signs of success after 90 days

- Everyone on the team knows the main journey's SLO and how much error budget is left today.
- Fewer alerts wake people up, and every paging alert has a runbook.
- Every Sev1 and Sev2 incident has a postmortem with tracked action items.
- One failure drill has been run, and its findings have been fixed.
