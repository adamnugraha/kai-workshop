# Templates

These templates accompany the session **Achieving 99.9% Availability and Beyond**. They are all plain Markdown, so they are easy to copy into Confluence, SharePoint, Notion, a Git wiki or whatever document your team uses. The examples use the fictional RelNusa application from the lab; replace them with your own services.

| Template | Used for | When |
|---|---|---|
| [System design worksheet](system-design-worksheet.md) | Targets per journey, availability chain math, failure domains, busiest-minute capacity, data consistency, the technology stack and the ten design review questions | Before building or modernizing a system, and at every architecture review |
| [SLO worksheet](slo-worksheet.md) | Deriving SLIs, SLOs, error budgets and alert thresholds from one user journey | When setting or reviewing SLOs |
| [Error budget policy](error-budget-policy.md) | Release rules agreed by the business and IT for when the failure allowance runs low | Once, before the next incident; reviewed every quarter |
| [Severity matrix](severity-matrix.md) | Incident severity levels, roles, response targets and communication patterns | Once, then used in every incident |
| [Alert runbook](alert-runbook.md) | Diagnosis and recovery steps for one alert | For every alert that can wake someone up |
| [Postmortem](postmortem.md) | Blameless incident reports with measurable follow-up | After every Sev1 and Sev2 incident, and after every game day |
| [Game day plan](game-day-plan.md) | Planned, safe failure drills | At least once a quarter |
| [Modernization scorecard](modernization-scorecard.md) | Assessing applications and choosing the first function to separate from the monolith | When drawing up a modernization plan |
| [90-day plan](90-day-plan.md) | The 30-, 60- and 90-day steps for getting started with SRE | At the start of the program |

## How to use them

1. For a new system or one about to be modernized, start with the **system design worksheet**: targets, math and risks before choosing technology.
2. Start the **SLO worksheet** with just one user journey. One SLO that is used is worth more than ten that only exist on paper.
3. Agree on the **error budget policy** and the **severity matrix** with the business owner before the next major incident. Decisions agreed in calm times are much easier to carry out in a crisis.
4. Write a **runbook** for every alert with *page* severity. An alert without a runbook should be downgraded to a ticket.
5. Practice all of it through **game days**, then improve these templates based on what the drills reveal.

Fields to fill in are marked `[...]`. Example figures are for illustration only.
