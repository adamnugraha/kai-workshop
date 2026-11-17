<p align="center">
  <img src="docs/assets/logo.svg" width="96" alt="RelNusa Availability Lab">
</p>

<h1 align="center">RelNusa Availability Lab</h1>

<p align="center">
  <em>A fictional train-ticket site, built twice, with the tools that measure it, release it and break it.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/talk-Achieving%2099.9%25%20Availability-E4002B?style=flat-square" alt="Talk: Achieving 99.9% Availability and Beyond">
  <img src="https://img.shields.io/badge/designs-legacy%20and%20modern-1F2026?style=flat-square" alt="Two designs: legacy and modern">
  <img src="https://img.shields.io/badge/live%20demos-5-10b981?style=flat-square" alt="Five live demos">
  <img src="https://img.shields.io/badge/SLOs-3-38a3f5?style=flat-square" alt="Three SLOs">
  <br>
  <img src="https://img.shields.io/badge/Kubernetes-k3s%201.36%20in%20k3d-38a3f5?style=flat-square" alt="k3s 1.36 in k3d">
  <img src="https://img.shields.io/badge/Go-1.26-f5a524?style=flat-square" alt="Go 1.26">
  <img src="https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-a78bfa?style=flat-square" alt="Ubuntu 22.04 or 24.04">
  <img src="https://img.shields.io/badge/license-Apache%202.0-6f7484?style=flat-square" alt="Apache License 2.0">
</p>

<p align="center">
  <img src="docs/assets/hero.png" width="900" alt="RelNusa Availability Lab: what it takes to run a booking site at 99.9% availability. The same Go code runs as a single-server monolith and as a three-zone design. Two designs side by side, five live demos (a ticket rush, releases, a lost server, a slow bank, a database failover), three SLOs with error budgets and burn-rate alerts to Telegram, and one VM that installs in about 20 minutes with every part open source. Beside it, the modern site after a booking, with each request it made.">
</p>

<p align="center">
  <a href="#what-it-is">What it is</a> &middot;
  <a href="#how-it-works">How it works</a> &middot;
  <a href="#what-you-see">What you see</a> &middot;
  <a href="#try-it">Try it</a> &middot;
  <a href="#run-the-demos">Run the demos</a> &middot;
  <a href="#slos-and-alerts">SLOs</a> &middot;
  <a href="#for-your-team">For your team</a> &middot;
  <a href="#extend-it">Extend</a> &middot;
  <a href="#explore-the-code">Explore</a>
</p>

---

## What it is

This lab accompanies the session **Achieving 99.9% Availability and Beyond**. It runs a fictional train-ticket booking site called **RelNusa** in two architectures on one Linux machine: a legacy single-server monolith and a modern design spread over three zones. Both run the same Go program, so every difference you see comes from the design. Around them sit the tools that site reliability engineering (SRE) teams use to measure, alert, release safely and practice failures. Every component is open source, so you can reinstall it in your own data center, on VMware or in any cloud.

| Part | What runs | What it shows |
|---|---|---|
| Legacy system | One monolith process and one database on a single node | Common legacy patterns: database row locks held while calling the bank, no cache, no queue, no timeouts, deployments by stopping and restarting |
| Modern system | A gateway with a virtual waiting room, a search service with a cache, a booking service with a payment queue, a payment worker with a circuit breaker, and PostgreSQL with one primary, two replicas and automatic failover | Architecture patterns that raise availability |
| Operations | Prometheus, Grafana, Alertmanager (to Telegram), OpenTelemetry and Jaeger, SLOs and error budgets (Sloth), progressive delivery (Argo Rollouts), load testing (k6), failure experiments (Chaos Mesh) | How to measure, alert, release safely and practice handling failures |
| Simulated bank | A mock payment provider that can be made slow, error-prone or unavailable | An external dependency outside our control |

> RelNusa is a fictional application. Its train names, prices and brand are invented and do not represent any organization's systems.

Tested versions are pinned in `lab.sh` and the manifests: k3s 1.36.5 in k3d 5.8.3, the kube-prometheus-stack chart 91.9.0, CloudNativePG (chart 0.29.1) with PostgreSQL 17.10, Redis 7.4, Argo Rollouts (chart 2.43.2), Chaos Mesh (chart 2.8.4), the OpenTelemetry Collector 0.160.0, Jaeger 2.17.0, Sloth 0.16.0, k6 1.8.1 and Go 1.26.

## How it works

<p align="center">
  <img src="docs/assets/architecture.png" width="900" alt="Architecture. Passengers, simulated by k6 load scripts or using a browser, reach one Traefik ingress that routes by host name, retries a failed connection and counts every request. The legacy site runs on one node, zone-b: a monolith with search, booking and payment in one process and a pool of 20 database connections, and one PostgreSQL instance with no replica. It breaks when a slow bank keeps the seat locked and a connection busy, when a rush uses up the 20 connections so search stalls too, when its one node stops, and for about 15 seconds at every release. The modern site runs over three zones: a gateway with a virtual waiting room for about 120 bookings a second, search with two to six replicas, a Redis cache, a stale copy and read replicas, booking with four replicas that holds the seat in one statement, queues the payment and is released as a canary, a data layer of Redis for cache and payment queue and PostgreSQL with one primary and two replicas and automatic failover, and a payment worker with an 800 millisecond timeout, a circuit breaker and an idempotency key. Both call a simulated bank that can be normal, slow, error-prone or down. Measuring and alerting: Prometheus and Sloth SLO rules, Grafana, Alertmanager to Telegram, the OpenTelemetry Collector to Jaeger. Change and test: Argo Rollouts, Chaos Mesh, k6. Underneath: k3s in Docker via k3d on one VM, three nodes labelled zone-a, zone-b and zone-c, HTTPS from Let's Encrypt via sslip.io, and lab.sh.">
</p>

Both sites sit behind the same Traefik ingress, so every request is measured at the same front door. The legacy site keeps everything on one node, which a demo stops on purpose. The modern site spreads the same work over three zones and adds four things:

- **A waiting room in front of booking.** The gateway admits about 120 bookings a second and gives everyone else a queue position, so a rush never reaches the database at full force.
- **Hold the seat first, pay afterwards.** Booking takes the seat in one SQL statement, puts the payment on a Redis stream and answers at once. A worker charges the bank with a timeout, a circuit breaker and an idempotency key.
- **Search that survives a slow database.** Search answers from a Redis cache, keeps an older copy for when the database is slow, and reads from replicas.
- **A database that fails over by itself.** PostgreSQL runs as one primary and two replicas under CloudNativePG, which promotes a replica when the primary fails.

The difference shows best in a single booking:

<p align="center">
  <img src="docs/assets/booking.png" width="900" alt="One booking, two designs. Legacy: 1, lock the seat row with SELECT FOR UPDATE; 2, call the bank with no timeout, 120 milliseconds or 3 seconds when the bank is slow; 3, save and commit with UPDATE, INSERT and COMMIT; 4, answer 201 PAID only after the bank has answered. During steps 1 to 3 the seat row is locked, one of 20 database connections is busy and the passenger waits. Modern: 1, admit or queue, about 120 bookings a second, the rest get QUEUED; 2, hold the seat in one SQL statement, done in milliseconds, which is the only time the lock is held; 3, queue the payment with XADD to the payments stream; 4, answer 202 HELD before the bank is called. In the background, 5, the worker reads the job and charges the bank with an 800 millisecond timeout behind a circuit breaker; 6, it marks the booking PAID, and the page, which asks every 1.5 seconds, shows the e-ticket. If the bank is slow or down, the job stays in the queue and is tried again; the booking id is the bank's idempotency key, so a retry never charges twice, and unpaid holds expire after 10 minutes.">
</p>

Under a rush, the legacy design runs out of its 20 database connections while each one waits for the bank, and the search page stalls with them. The modern design holds the lock for one statement, so a slow bank only delays the e-ticket.

The operations tools are wired the way a production team would wire them:

<p align="center">
  <img src="docs/assets/alerts.png" width="900" alt="From a line of code to an alert. Code: the payment worker counts every attempt by its outcome in payment_attempts_total. Scrape: Prometheus reads /metrics on every pod every 5 seconds through the PodMonitor relnusa. Target: the SLO file relnusa-slos.yaml says 99.9% of payment attempts succeed. Rules: Sloth writes error ratios over windows from 5 minutes to 30 days. Burn rate: page when 5 minutes and 1 hour burn above 14.4 times, or 30 minutes and 6 hours above 6 times. Route: Alertmanager sends alerts with an SLO label to Telegram. The same metrics also drive Grafana's three dashboards and Argo Rollouts' canary analysis, which checks every 15 seconds and stops a release when more than 5% of the new version's requests fail. Traces take a separate path, from the OpenTelemetry Collector to Jaeger, for 10% of modern requests and 20% of legacy ones. Availability and latency follow the same chain but are measured at Traefik, so a 503 sent when no pod is ready still counts against the budget.">
</p>

Grafana and the canary checks read the same Prometheus data as the alerts, so a release decision and a page rest on the same numbers.

## What you see

Everything below comes from a test run of the lab. The two sites need no login; Grafana is open for viewing.

<table>
  <tr>
    <td width="50%"><img src="docs/assets/screens/site-legacy.png" alt="The legacy site: search results for Jakarta to Yogyakarta, the booking panel and the request log, served by one process from the database."></td>
    <td width="50%"><img src="docs/assets/screens/site-modern.png" alt="The modern site after a booking: the e-ticket code, and in the request log a POST that answered 202 followed by the status checks."></td>
  </tr>
  <tr>
    <td><b>The legacy site.</b> One process answers search and booking from the database; the request log on the right shows every call and its time.</td>
    <td><b>The modern site.</b> Search answers from the cache, the booking answers 202 at once and the e-ticket follows from the payment queue.</td>
  </tr>
  <tr>
    <td><img src="docs/assets/screens/dashboard-before-after.png" alt="Grafana dashboard RelNusa 1, before vs after: successful requests, p95 response time, server errors and requests per second for both sites, measured at Traefik."></td>
    <td><img src="docs/assets/screens/dashboard-slos.png" alt="Grafana dashboard RelNusa 2, SLOs and error budgets: the alerts that are firing, and for each SLO its target, the last five minutes, the budget left over 30 days and the burn rates."></td>
  </tr>
  <tr>
    <td><b>RelNusa 1 &middot; Before vs after.</b> Both sites at the front door: successful requests, p95 response time, server errors and traffic.</td>
    <td><b>RelNusa 2 &middot; SLOs and error budgets.</b> Target, budget left and burn rate for each SLO, and the alerts on their way to Telegram; here after a round of demos.</td>
  </tr>
</table>

<p align="center">
  <img src="docs/assets/screens/dashboard-inside-modern.png" width="700" alt="Grafana dashboard RelNusa 3, inside the modern architecture: node status with one node down and back, pods per service, search replicas, the circuit breaker to the bank, payment attempts by outcome, payments waiting in the queue, double charges prevented and booking response time.">
  <br>
  <b>RelNusa 3 &middot; Inside the modern architecture.</b> Nodes, pods per service, autoscaling, the circuit breaker, payment outcomes and the queue; here just after a stopped node came back.
</p>

Also in the lab: Jaeger for traces, Argo Rollouts for releases, Chaos Mesh for failure experiments, Prometheus and Alertmanager. They sit behind one login at `https://<tool>.<ip>.sslip.io`, and `./lab.sh info` prints every address with the password.

## Try it

You need one Ubuntu 22.04 or 24.04 VM with 8 vCPUs, 32 GB of RAM and a 100 GB disk (4 vCPUs and 16 GB for the `small` profile), with TCP 80 and 443 open.

<p align="center">
  <img src="docs/assets/install-path.png" width="900" alt="From an empty VM to the first demo, in six steps. 1: get a VM, Ubuntu 22.04 or 24.04 with 8 vCPUs, 32 GB and a 100 GB disk, or 4 vCPUs and 16 GB for the small profile. 2: install the tools, Docker, k3d, kubectl, Helm and plugins, with sudo ./lab.sh install-deps. 3: start the lab with ./lab.sh up, 15 to 25 minutes the first time. 4: open it, ./lab.sh info prints every address and the password. 5: check it with ./lab.sh preflight before going on stage. 6: run the demos, then ./lab.sh reset for the next round. Or in one go: curl the bootstrap script from this repository and pipe it to sudo bash.">
</p>

In one go (the same line works as *user data* on AWS or as a *startup script* on Google Cloud):

```bash
curl -fsSL https://raw.githubusercontent.com/adamnugraha/kai-workshop/main/bootstrap.sh | sudo bash
```

Or step by step:

```bash
git clone https://github.com/adamnugraha/kai-workshop.git && cd kai-workshop
cp lab.env.example lab.env     # choose LAB_ACCESS, the Telegram token, the small profile
sudo ./lab.sh install-deps     # Docker, k3d, kubectl, helm, kubectl plugins
./lab.sh up                    # 15 to 25 minutes on the first install
./lab.sh info                  # addresses and the password
```

In the default `public` mode, every address uses the VM's public IP through [sslip.io](https://sslip.io), with free HTTPS certificates from Let's Encrypt, so there is no DNS to set up:

| Address | Contents | Login |
|---|---|---|
| `https://legacy.<ip>.sslip.io` | The legacy site | Not needed |
| `https://app.<ip>.sslip.io` | The modern site | Not needed |
| `https://grafana.<ip>.sslip.io` | Dashboards | View without logging in; edit as `admin` |
| `https://jaeger.<ip>.sslip.io`, `chaos.`, `rollouts.`, `prometheus.`, `alertmanager.` | Operator tools | `admin` and the password from `./lab.sh info` |

| Read next | For |
|---|---|
| [docs/install.md](docs/install.md) | Requirements, the SSH tunnel mode for servers without a public IP, updates, certificates and everyday commands |
| [docs/aws-setup.md](docs/aws-setup.md), [docs/gcp-setup.md](docs/gcp-setup.md), [docs/server-setup.md](docs/server-setup.md) | Step by step on AWS, on Google Cloud or on your own server |
| [docs/telegram-setup.md](docs/telegram-setup.md) | Alerts in a Telegram group, for you or for the whole audience |

## Run the demos

| Demo | Command | What you see |
|---|---|---|
| 1 &middot; Ticket rush | `./lab.sh spike legacy`, then `./lab.sh spike modern` | Legacy: response times climb to 10 seconds or more, 504 errors appear, and the whole site slows down, search included. Modern: no errors; buyers above capacity wait in the virtual queue and search adds replicas |
| 2 &middot; Releases | `./lab.sh legacy-deploy`, then `./lab.sh release good` and `./lab.sh release bad` | The legacy site is down for about 15 seconds. The modern canary moves step by step with no errors, and the analysis stops the buggy version before most users see it |
| 3 &middot; A lost server | `./lab.sh node-down`, later `./lab.sh node-up` | The zone-b node stops: the legacy site goes down completely and the modern site keeps serving |
| 4 &middot; Game day: a slow bank | `./lab.sh chaos bank-slow`, then `./lab.sh chaos stop` | The circuit breaker opens, seats can still be held, and the ticket issuance SLO alert reaches Telegram |
| 5 &middot; Database failover | `./lab.sh chaos kill-db-primary`, then `./lab.sh chaos stop` | A replica becomes the primary within seconds; search keeps working from the cache |

Between rounds, `./lab.sh reset` clears bookings, refills seats and puts the bank back to normal. Before going on stage, `./lab.sh preflight` checks everything at once; `./lab.sh help` lists every command. Demo 4 needs the `netem` kernel module on the VM; without it, `./lab.sh bank slow` gives the same fault inside the bank. The presenter's steps for all five demos, with what to point at and what to do when something goes wrong, are in [demos/RUNBOOK.md](demos/RUNBOOK.md).

## SLOs and alerts

| Service | SLO | Target | Measured at |
|---|---|---|---|
| relnusa-modern, relnusa-legacy | Availability: requests without a server error | 99.9% | Traefik (the user's side) |
| relnusa-modern, relnusa-legacy | Latency: requests under 500 ms | 99% | Traefik |
| relnusa-modern | Ticket issuance: payment attempts that succeed | 99.9% | Payment worker |

The definitions are in [`k8s/slo/relnusa-slos.yaml`](k8s/slo/relnusa-slos.yaml). Sloth turns them into the Prometheus rules in `k8s/slo/rules/`, including the multi-window, multi-burn-rate alerts described in Google's Site Reliability Workbook. Only alerts that belong to an SLO reach Telegram; every other alert stays on the dashboards.

## For your team

### Templates

The [templates/](templates/README.md) folder holds plain Markdown templates, easy to copy into Confluence, SharePoint, Notion or a Git wiki. The examples use RelNusa; replace them with your own services.

| Template | Use it for |
|---|---|
| [System design worksheet](templates/system-design-worksheet.md) | Targets per journey, availability chain math, failure domains, busiest-minute capacity and the design review questions |
| [SLO worksheet](templates/slo-worksheet.md) | SLIs, SLOs, error budgets and alert thresholds from one user journey |
| [Error budget policy](templates/error-budget-policy.md) | Release rules agreed by the business and IT for when the budget runs low |
| [Severity matrix](templates/severity-matrix.md) | Incident levels, roles, response targets and communication |
| [Alert runbook](templates/alert-runbook.md) | Diagnosis and recovery steps for one alert |
| [Postmortem](templates/postmortem.md) | Blameless incident reports with measurable follow-up |
| [Game day plan](templates/game-day-plan.md) | Planned, safe failure drills |
| [Modernization scorecard](templates/modernization-scorecard.md) | Choosing the first function to separate from a monolith |
| [90-day plan](templates/90-day-plan.md) | The first 30, 60 and 90 days of an SRE practice |

### From the lab to production

| In the lab | Production equivalent |
|---|---|
| k3d on one VM | A Kubernetes cluster across several servers or zones (Rancher, OpenShift, EKS, GKE, AKS) |
| CloudNativePG | The same operator in production, or a managed database service with replicas across zones |
| A single Redis instance | Redis with replication (Sentinel or cluster mode), or a managed service |
| Waiting room in the gateway | A virtual waiting room in the CDN or API gateway |
| Simulated bank | Real payment partners; the timeout, circuit breaker and idempotency key patterns stay the same |
| Telegram | The team's on-call channel (Telegram, Slack, PagerDuty, Opsgenie) |

## Extend it

Most changes are one line in a manifest or one new file, applied with a single `lab.sh` command. Each row links to step-by-step instructions in [docs/extending.md](docs/extending.md).

| You want to | Change | Guide |
|---|---|---|
| Let more or fewer bookings through the waiting room | `ADMIT_RATE` in `k8s/apps/modern.yaml` | [Waiting room](docs/extending.md#change-how-many-bookings-the-waiting-room-admits) |
| Change the bank timeout, worker concurrency or breaker | the `payment-worker` settings in `k8s/apps/modern.yaml` | [Payment worker](docs/extending.md#tune-the-payment-worker) |
| Change the canary steps or the error threshold | `k8s/apps/booking-rollout.tpl.yaml` | [Canary release](docs/extending.md#change-the-canary-release) |
| Add or change an SLO | `k8s/slo/relnusa-slos.yaml`, then Sloth | [SLOs](docs/extending.md#add-or-change-an-slo) |
| Add a dashboard panel | `tools/make_dashboards.py` | [Dashboards](docs/extending.md#add-a-dashboard-panel) |
| Add a failure experiment | a new file in `chaos/` | [Experiments](docs/extending.md#add-a-failure-experiment) |
| Change the ticket rush or add a load scenario | `./lab.sh spike` options, or `load/` | [Load](docs/extending.md#change-the-ticket-rush-or-add-a-load-scenario) |
| Send alerts to Slack, e-mail or a pager | `alertmanager_values` in `lab.sh` | [Alerts](docs/extending.md#send-alerts-to-another-channel) |
| Change the application or the bank | `app/`, then `./lab.sh rebuild` | [Application](docs/extending.md#change-the-application) |

## Explore the code

| Start here | To understand |
|---|---|
| [`app/internal/store/store.go`](app/internal/store/store.go) | `BookLegacy` and `Hold`: the two ways to take a seat |
| [`app/internal/modes/gateway.go`](app/internal/modes/gateway.go) | The virtual waiting room |
| [`app/internal/modes/search.go`](app/internal/modes/search.go) | Search with a cache, a stale copy and a circuit breaker |
| [`app/internal/modes/payment.go`](app/internal/modes/payment.go) | The payment worker: queue, timeout, breaker and retries |
| [`app/internal/obs/obs.go`](app/internal/obs/obs.go) | The metrics, traces, logs and health checks every role gets |
| [`k8s/apps/booking-rollout.tpl.yaml`](k8s/apps/booking-rollout.tpl.yaml) | The canary release and its analysis |
| [`k8s/slo/relnusa-slos.yaml`](k8s/slo/relnusa-slos.yaml) | The three SLOs |
| [`lab.sh`](lab.sh) | Installing the lab and running every demo |

```text
app/            application code (Go), one image for every role
k8s/cluster/    Traefik ingress settings
k8s/platform/   Helm values for monitoring, database, chaos and releases; collector and Jaeger
k8s/apps/       simulated bank, legacy system, modern system, metric monitors
k8s/slo/        SLO definitions and the generated Prometheus rules
k8s/dashboards/ Grafana dashboards (generated by tools/make_dashboards.py)
load/           k6 scripts: everyday traffic and the ticket rush
chaos/          Chaos Mesh experiments
demos/          the presenter's demo runbook
docs/           install, cloud and Telegram guides, the extension guide, and the figures on this page
templates/      templates for system design, SLOs, error budgets, incidents, postmortems, game days and modernization
lab.sh          a single entry point to install the lab and run the demos
```

Run the unit tests with `cd app && go test ./...`. The figures on this page are drawn from HTML in [`docs/assets/src/`](docs/assets/src); `node docs/assets/src/render.js` redraws them.

## License

Apache License 2.0. See [LICENSE](LICENSE).
