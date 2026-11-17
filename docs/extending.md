# Extending the lab

Most changes are a line in a manifest or a small file, followed by one `lab.sh` command that applies it to the running cluster. Code changes are needed only for new behaviour in the application itself. Every command runs on the lab VM from the repository folder.

| You want to | Change | Then run |
|---|---|---|
| [Let more or fewer bookings through the waiting room](#change-how-many-bookings-the-waiting-room-admits) | `ADMIT_RATE` in `k8s/apps/modern.yaml` | `./lab.sh apply` |
| [Tune the payment worker](#tune-the-payment-worker) | `BANK_TIMEOUT_MS` and friends in `k8s/apps/modern.yaml` | `./lab.sh apply` |
| [Change the canary release](#change-the-canary-release) | `k8s/apps/booking-rollout.tpl.yaml` | `./lab.sh release undo` |
| [Add or change an SLO](#add-or-change-an-slo) | `k8s/slo/relnusa-slos.yaml` | `./k8s/slo/generate.sh`, `./lab.sh apply-content` |
| [Add a dashboard panel](#add-a-dashboard-panel) | `tools/make_dashboards.py` | `python3 tools/make_dashboards.py`, `./lab.sh apply-content` |
| [Add a failure experiment](#add-a-failure-experiment) | a new file in `chaos/` | `./lab.sh chaos <name>` |
| [Change the ticket rush or add a load scenario](#change-the-ticket-rush-or-add-a-load-scenario) | `load/` | `./lab.sh spike ...` |
| [Send alerts to another channel](#send-alerts-to-another-channel) | `alertmanager_values` in `lab.sh` | `./lab.sh alerts` |
| [Change the application](#change-the-application) | `app/` | `./lab.sh rebuild` |

## Change how many bookings the waiting room admits

The gateway admits booking requests with a token bucket and answers the rest with `QUEUED`, a queue position and a time to retry; the page then retries by itself.

1. In [`k8s/apps/modern.yaml`](../k8s/apps/modern.yaml), find the `gateway` Deployment. `ADMIT_RATE` is the number of bookings each replica lets through per second (60) and `ADMIT_BURST` the short burst it allows on top (30). The gateway runs two replicas, so the site admits about 120 bookings per second in total.
2. Set the rate from what your database handled in a load test, not from a guess. The waiting room protects the database only if it admits less than the database can serve.
3. Run `./lab.sh apply` (about two minutes).
4. Run `./lab.sh spike modern` and watch *Virtual waiting room (modern app)* on the *RelNusa 1* dashboard: `admitted` should level off at the new rate while `queued` takes the rest.

## Tune the payment worker

The payment worker takes held bookings from the Redis stream `payments` and charges the bank.

1. In [`k8s/apps/modern.yaml`](../k8s/apps/modern.yaml), the `payment-worker` Deployment carries three settings:
   - `BANK_TIMEOUT_MS` (800): how long one bank call may take before it counts as failed.
   - `WORKER_CONCURRENCY` (16): how many bank calls each worker makes at once.
   - `BREAKER_OPEN_MS` (10000): how long the circuit breaker stays open before it lets three trial calls through.
2. Run `./lab.sh apply`.
3. Try it with `./lab.sh bank slow` (each bank answer takes about 3 seconds) and watch *Circuit breaker to the bank* and *Payments waiting in the queue* on the *RelNusa 3* dashboard. Put the bank back with `./lab.sh bank normal`.

When the breaker opens is set in code: it opens when at least half of the last 10 bank calls failed, with at least 5 calls seen. Change that in [`app/internal/modes/payment.go`](../app/internal/modes/payment.go) and follow [Change the application](#change-the-application).

## Change the canary release

New booking versions go out as an Argo Rollout: 25% of the pods first, a pause while Prometheus checks the new version's errors, then 50% and 100%.

1. In [`k8s/apps/booking-rollout.tpl.yaml`](../k8s/apps/booking-rollout.tpl.yaml):
   - `steps` sets the weights and pauses (25%, 60 seconds, 50%, 30 seconds, 100%).
   - The `AnalysisTemplate` named `booking-error-rate` checks the new version every 15 seconds (`interval`). A check fails when more than 5% of its booking requests end in a server error (`successCondition`), and with `failureLimit: 1` the second failed check stops the release.
2. The file is a template that `lab.sh` fills in with the version, so apply it through a release: `./lab.sh release undo` applies it with the stable version v1.
3. Try it with `./lab.sh release good`, then `./lab.sh release bad`, and watch the Argo Rollouts page or `kubectl argo rollouts get rollout booking -n modern --watch`.

## Add or change an SLO

SLOs are written in [Sloth](https://github.com/slok/sloth)'s format, and Sloth turns them into Prometheus recording rules and multi-window, multi-burn-rate alerts.

1. Edit [`k8s/slo/relnusa-slos.yaml`](../k8s/slo/relnusa-slos.yaml). Each SLO has a target (`objective`), a query for bad events (`errorQuery`), a query for all events (`totalQuery`) and alert labels. Copy an existing SLO as a start: availability and latency are measured at Traefik, ticket issuance at the payment worker.
2. Install the Sloth command-line tool (the rules in this repository come from v0.16.0, from [Sloth's releases](https://github.com/slok/sloth/releases)).
3. Run `./k8s/slo/generate.sh`. It rewrites `k8s/slo/rules/relnusa-slo-rules.yaml`; do not edit that file by hand.
4. Run `./lab.sh apply-content` to load the rules into Prometheus.
5. Open the *RelNusa 2* dashboard. Its SLO list is read from the rules, so the new SLO appears by itself. Alerts of the new SLO reach Telegram without any change, because every alert with an SLO label is routed there.

The [SLO worksheet](../templates/slo-worksheet.md) walks through choosing the events and the target before writing them down.

## Add a dashboard panel

The four dashboards (the overview and *RelNusa 1*, *2* and *3*) are generated by one script, so they stay the same on every install.

1. Edit [`tools/make_dashboards.py`](../tools/make_dashboards.py). Each dashboard is a function (`d00` to `d03`) that adds panels with helpers such as `timeseries`, `stat`, `gauge` and `table`; each panel takes a PromQL expression.
2. Run `python3 tools/make_dashboards.py`. It rewrites `k8s/dashboards/relnusa-dashboards.yaml`, one ConfigMap per dashboard.
3. Run `./lab.sh apply-content`. Grafana's sidecar picks the ConfigMaps up by itself.

Make dashboard changes in the script rather than in Grafana's editor, so they survive the next apply.

## Add a failure experiment

Failure experiments are Chaos Mesh resources, one file per experiment in [`chaos/`](../chaos).

1. Copy the closest example:
   - [`kill-search.yaml`](../chaos/kill-search.yaml) kills one pod (`PodChaos`);
   - [`kill-db-primary.yaml`](../chaos/kill-db-primary.yaml) kills the database primary;
   - [`bank-slow.yaml`](../chaos/bank-slow.yaml) adds network delay (`NetworkChaos`).
2. Save it as `chaos/<name>.yaml` with `metadata.name` set to the same name, and change the selector and the action.
3. Run `./lab.sh chaos <name>`. `./lab.sh chaos list` shows every experiment and what is running; `./lab.sh chaos stop` removes them all.

Network experiments need the `netem` kernel module on the VM; `lab.sh` loads it when it can and tells you when the kernel has none.

## Change the ticket rush or add a load scenario

Load comes from [k6](https://k6.io) scripts in [`load/`](../load): `ticket-rush.js` for the demos, `steady.js` for the background traffic and `lib.js` for what they share. k6 runs in a container that mounts the folder as `/scripts` and sends its results to Prometheus, so the dashboards show what the simulated passengers saw.

- Change the rush without editing anything: `./lab.sh spike modern 300 120s` sends up to 300 new buyers per second and holds the peak for 120 seconds (the defaults are 150 and 90s).
- For a new scenario, add `load/<name>.js` and a command in `lab.sh` modelled on `cmd_spike`, which runs `k6_run ... run --out experimental-prometheus-rw /scripts/ticket-rush.js`.

## Send alerts to another channel

Alert routing is written by the `alertmanager_values` function in [`lab.sh`](../lab.sh): alerts with an `sloth_slo` label go to the `telegram` receiver and every other alert goes to a receiver that does nothing.

1. Add a receiver in that function, for example Slack, e-mail or PagerDuty, in [Alertmanager's configuration format](https://prometheus.io/docs/alerting/latest/configuration/), and route the SLO alerts to it.
2. Run `./lab.sh alerts`.
3. Run `./lab.sh telegram-test`, which sends a test alert through Alertmanager, to check the route.

Keep the rule that only SLO alerts reach a person; the [alert runbook](../templates/alert-runbook.md) and [severity matrix](../templates/severity-matrix.md) templates help decide what each one should say.

## Change the application

One Go program in [`app/`](../app) runs every role: `relnusa monolith|gateway|search|booking|payment-worker|banksim|reset|migrate`. The same image runs in every pod, so a comparison between the two sites is about the design, not about different code.

1. Change the code. The places that matter most:
   - [`app/internal/store/store.go`](../app/internal/store/store.go): `BookLegacy` and `Hold`, the two ways to take a seat.
   - [`app/internal/modes/`](../app/internal/modes): one file per role.
   - [`app/internal/obs/obs.go`](../app/internal/obs/obs.go): the metrics, traces and health checks every role gets.
2. Run the unit tests: `cd app && go test ./...`.
3. Run `./lab.sh rebuild`. It builds the image, loads it on every node and rolls the pods.

The simulated bank is a role of the same program ([`app/internal/modes/banksim.go`](../app/internal/modes/banksim.go)). `./lab.sh bank normal|slow|errors|down` switches its mode while the lab runs.
