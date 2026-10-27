# Presenter runbook

How to run the talk's three parts and five live demos, what to point at, what to do when something goes wrong, and how to reset between rounds. Slide numbers refer to the two session decks: Session 1 holds part 1 (system design) and part 2 (modernisation), Session 2 holds part 3 (SRE). Every command runs on the lab VM from the repository folder.

## The two hours at a glance

| Time | Part | Live in the lab |
|---|---|---|
| 0:00–0:05 | Opening (Session 1 deck, slides 1–2) | Grafana *RelNusa · Ringkasan* on the second screen |
| 0:05–0:25 | Part 1 · System design (Session 1 deck, slides 3–16) | None needed; optional one-minute tour of *RelNusa 3* on slide 14 |
| 0:25–1:00 | Part 2 · Modernisation (Session 1 deck, slides 17–29) | Demo 1 ticket rush · Demo 2 releases · Demo 3 node failure |
| 1:00–1:10 | Break | Reset checklist (below); *RelNusa 1* stays on screen |
| 1:10–1:50 | Part 3 · SRE (Session 2 deck) | Demo 4 bank slowdown game day · Demo 5 database failover |
| 1:50–2:00 | Roadmap, take-home, Q&A | QR code to this repository |

Part 2 is tight with three demos in 35 minutes: use the short Demo 1 runs (`./lab.sh spike legacy 150 45s`, then the same for `modern`). If time still runs short, drop Demo 5 first, then the `release good` step of Demo 2. Slide 9 (the Access by KAI figures) is optional. Demo 1 and Demo 4 carry the story of their parts.

## Before the day

- [ ] **Wednesday rehearsal:** run all five demos end to end on the VM. Note the real numbers for the *result1* slide (Session 1) and the *timeline4* slide (Session 2).
- [ ] **Backup videos:** record each demo during the rehearsal (screen recording of Grafana plus the terminal). Keep the files on the laptop, not on the VM.
- [ ] **Telegram:** create the group, add the bot, and put the token and chat ID in `lab.env`. Then run `./lab.sh alerts` and `./lab.sh telegram-test`. Make a join link for the group if the audience should receive alerts on their phones.
- [ ] **Freeze:** after the rehearsal, change nothing on the VM except `./lab.sh reset`.

## Thursday morning, one hour before

1. Start the VM (if it was stopped) and wait about five minutes for the boot service to bring the cluster up. SSH in for the terminal (or use the cloud console's browser shell).
2. On the VM:
   ```bash
   cd /opt/kai-workshop        # or wherever you cloned it
   ./lab.sh info               # the addresses for the browser tabs, and the tools password
   ./lab.sh traffic start      # if it is not already running; it should run for an hour before Session 2
   ./lab.sh reset
   ./lab.sh preflight          # must end with "ready"
   ./lab.sh telegram-test      # message arrives in the group within about 15 seconds
   ```
   `preflight` checks nodes, pods, the sites, the login on the operator tools, that the lab answers at its public address, the HTTPS certificates, the booking release, the database, chaos experiments, the bank, background traffic, Prometheus targets, the five SLOs, firing alerts, Telegram and network fault support.
3. Browser tabs, in this order (Chrome or Edge, zoom 125% so the back row can read the panels). The addresses below are written `<site>.<domain>`; `./lab.sh info` prints the real ones (`https://app.<ip>.sslip.io` in public mode, `http://app.localhost:8080` over a tunnel):
   1. The session deck
   2. Grafana · `RelNusa · 1 · Sebelum vs sesudah` (time range: last 15 minutes, refresh 5s)
   3. Grafana · `RelNusa · 2 · SLO dan error budget` (last 30 minutes)
   4. Grafana · `RelNusa · 3 · Di dalam arsitektur modern` (last 15 minutes)
   5. `legacy.<domain>` and `app.<domain>` side by side
   6. `rollouts.<domain>` (namespace `modern`, rollout `booking`; log in once as `admin`)
   7. `jaeger.<domain>`
   8. `chaos.<domain>`
   9. The Telegram group (desktop app or web)
4. A terminal on the VM with a large font (at least 20 pt), the repository folder open.

## Session 1 · Part 1: system design

No demo; the lab appears as the worked example. Keep each slide to about 90 seconds. The story in one line: set the target from the passenger's side, do the availability arithmetic, design for the busiest minute, then choose the stack.

| Slides | Point to make |
|---|---|
| 4–6 | 99.9% is 44 minutes a month, measured as successful requests at the entrance, and a chain of five 99.9% parts is only 99.5% |
| 7–8 | Two ways out of the chain: redundancy (two independent 99% copies give 99.99%) and taking parts off the mandatory path (payment through a queue). Copies only help in different failure domains; for 99.9%, design to at least the zone level |
| 9–10 | Size for the busiest minute from passenger behaviour; scale the read path out, protect the write path with the waiting room. The numbers on slide 10 are an invented example, not KAI data |
| 11 | Seats must be exact, schedules may lag a few seconds, payment may follow later |
| 12–13 | The surge and failure patterns; all of them run in the lab |
| 14–15 | Reference architecture and stack table. Bold entries are what the lab uses. If time allows, switch to *RelNusa 3* for a minute to show the components running |
| 16 | The ten design review questions; the full worksheet is `templates/lembar-desain-sistem.md` |

## Session 1 · Part 2: modernisation

### Demo 1 · Ticket rush (slide 23, result on slide 24)

| | |
|---|---|
| Show | Grafana *RelNusa 1*, then both sites side by side |
| Run | `./lab.sh spike legacy`, wait for it to finish, then `./lab.sh spike modern` |
| Short version | `./lab.sh spike legacy 150 45s` and `./lab.sh spike modern 150 45s` |
| Duration | about 2 minutes per run with the default 90 s hold |

Point at, in order:
1. *Persentase permintaan berhasil*: the legacy line falls well below 100% within seconds.
2. *Waktu respons p95*: legacy climbs to several seconds and then to the 15 s timeout.
3. During the legacy run, open a search page on the legacy site. It stalls too, although only one train is being booked. That is the shared connection pool and row locks in the monolith.
4. Run the modern spike. The success line stays flat at 100% and p95 stays in milliseconds. Buyers above capacity land in the virtual waiting room panel instead of getting an error.

Expected (from the small test cluster, refresh on the VM): legacy loses tens of percent of requests with p95 in the 10–15 s range; modern loses none with p95 under 100 ms.

If it goes wrong: if k6 cannot start, check `docker ps` for a leftover `k6` container and remove it. If the modern run shows errors, check `./lab.sh status` for pods not ready, then play backup video 1.

### Demo 2 · Releases during peak hours (slide 27)

| Step | Run | What the audience sees |
|---|---|---|
| 1 | `./lab.sh legacy-deploy` | A gap of about 15 s in the legacy success line on *RelNusa 1* (stop, then start) |
| 2 | `./lab.sh release good` | Argo Rollouts: v2 at 25%, 60 s analysis, 50%, 30 s, 100%. Modern line stays green. About 3 minutes |
| 3 | `./lab.sh release bad` | v3 fails 30% of bookings. The analysis fails and Argo Rollouts aborts by itself within about a minute |
| After | `./lab.sh release undo` | Back to v1 |

Show the Argo Rollouts tab during steps 2 and 3, and *RelNusa 3 → Error booking per versi* for step 3. Only the canary share of users saw errors, and only for the length of one analysis run.

If it goes wrong: if the rollout looks stuck, run `kubectl argo rollouts get rollout booking -n modern` to see why. `./lab.sh release undo` always returns to a clean v1.

### Demo 3 · One server dies (slide 28)

| | |
|---|---|
| Show | *RelNusa 3 → Status node* and *Pod aplikasi modern yang melayani*, plus both sites |
| Run | `./lab.sh node-down`, talk through it for about a minute, then `./lab.sh node-up` |

What happens: the script first moves the database primary (and cluster DNS) off zone B if they are there, so this demo is about the application layer. Then the node stops.

Measured on the test cluster:

| After the stop | Legacy | Modern |
|---|---|---|
| 0–5 s | Every request fails from here on | New requests go to pods on the other nodes |
| 15–30 s | Still down | A handful of requests that were in flight on the dead node fail with 504 after the 15 s ingress timeout (about 10 requests in the test, a small dip on the success graph) |
| about 25 s | Still down | Kubernetes marks the node not ready; the ingress stops sending anything there |
| about 40 s | Still down | Replacement pods are ready on the other nodes |
| `node-up` + 35 s | Back | |

Be honest about the dip: the modern system is not magic, it loses the few requests that were inside the dead server. The difference is that it heals itself in seconds, while the legacy system waits for a person. If the replica database died with the node, searches are answered from the stale cache (fast, via the search circuit breaker) until it returns.

After `node-up`, give it about a minute before Demo 4 or the break. Check that `./lab.sh status` shows three ready nodes.

## Break · reset checklist

```bash
./lab.sh release undo       # if Demo 2 left anything behind
./lab.sh node-up 0          # if Demo 3 left the node down
./lab.sh reset              # bookings cleared, seats refilled, bank normal
./lab.sh chaos stop
./lab.sh preflight
```

Then switch the second screen to *RelNusa 2* and open the Telegram group.

Legacy page alerts from Demo 1 may still be firing; they clear by themselves within about 30 minutes. They are a useful talking point: the legacy app really did page someone.

## Session 2 · Part 3: SRE

### Demo 4 · Game day: the bank slows down (slides 13–15)

Hypothesis on slide 13: when the bank is slow, bookings keep working and a page alert arrives within three minutes.

| | |
|---|---|
| Show | *RelNusa 3 → Pembayaran dan bank*, then *RelNusa 2*, Jaeger, Telegram |
| Start the fault | `./lab.sh chaos bank-lambat` (or create a NetworkChaos in the Chaos Mesh UI to show the tool) |
| Fallback | `./lab.sh bank slow` (same effect inside the bank simulator; use it if `preflight` reported no netem) |
| Stop the fault | `./lab.sh chaos stop` (or `./lab.sh bank normal` for the fallback) |

Timeline measured on the test cluster, with background traffic running for more than an hour (refresh during the rehearsal and put the times on slide 15):

| Time | Event |
|---|---|
| T+0:00 | Fault starts: bank answers take 3 s, the payment worker gives up after 800 ms |
| T+0:20 | Both circuit breakers open (panel turns red). Bookings are still accepted and seats are held as "waiting for payment" |
| T+1:20 | Page alert *RelnusaModernPenerbitanTiket* fires; Telegram gets it about 10 s later. The 1-hour burn rate passes 14.4 at about T+1:15 |
| T+3:00 | Fault stopped |
| T+3:15 | Both breakers closed. The 190 payments that piled up are all paid by T+3:20, with no double charges (idempotency keys) |
| about T+33 | Alert resolves and Telegram gets the resolved message |

Why the alert stays on for half an hour: a 3-minute total outage also trips the second page rule (6 times the burn rate over 6 hours and 30 minutes), so the alert only resolves once the 30-minute window no longer contains the outage. The 5-minute burn rate drops back to 0 about 5 minutes after the fault stops. This is the multi-window design working as intended, and a good question to ask the audience.

Talking points while waiting:
- *Ketersediaan* on *RelNusa 2* stays green the whole time. The site never failed; only ticket issuance did. That is why there is a separate journey SLO.
- In Jaeger, pick service `payment-worker`, find a trace with an error, and show the bank span cut off at 800 ms.
- Try a booking on the modern site during the fault: it is accepted and shown as waiting for payment.
- Nothing about CPU or memory triggered anything.

Do not wait for the resolved message on stage. Move on to slide 15 and Demo 5; mention later in the session when it arrives.

### Demo 5 · Database primary dies (slide 16)

| | |
|---|---|
| Show | *RelNusa 3 → Peran instance database*, *Error booking per versi* and *Sumber jawaban pencarian* |
| Run | `./lab.sh chaos matikan-db-primary`, then `./lab.sh chaos stop` afterwards |

What happens: CloudNativePG notices the primary is gone and promotes the most up-to-date replica. Booking reconnects through the same `relnusa-db-rw` service. The old primary comes back as a replica by itself.

Measured on the test cluster (small profile, two database instances):

| After the kill | Event |
|---|---|
| 0–20 s | No primary. About 20 booking requests fail with 503 or 504 (around 5% of modern requests in that half minute) |
| about 20 s | The replica is promoted; bookings succeed again |
| 20–45 s | With no replica left, searches are answered from the stale cache (the search circuit breaker opens, so they stay fast) |
| about 45 s | The old primary is back as a replica; searches use the database again |

With the full profile (three instances) a replica remains for searches throughout. The talking point is the number: about 20 seconds of failed bookings, handled by software, against the hours a manual restore of the legacy database takes.

### Optional extras if there are questions

- `./lab.sh chaos matikan-search`: kills one search pod. Users notice nothing.
- `./lab.sh chaos matikan-payment-worker`: kills all payment workers. Jobs wait in the Redis stream and are paid when the new workers start. Discussion point: the ticket issuance SLO barely moves, because no payment attempts happen while no worker exists. Queue age is the signal for that case, which is why *Pembayaran menunggu di antrean* is on the dashboard.
- `./lab.sh bank errors`: half of the bank calls fail instead of being slow. Undo with `./lab.sh bank normal`.

## Troubleshooting on stage

| Symptom | Quick fix | If that fails |
|---|---|---|
| Browser cannot open the lab's addresses | Public mode: try from your phone on mobile data; if that works, the venue blocks sslip.io or ports 80/443, so use the hotspot. Tunnel mode: restart the SSH tunnel | Use the backup videos |
| Certificate warning, or `https://` does not open | Use the same address with `http://`; afterwards check `./lab.sh preflight` | |
| The public IP changed (no Elastic or static IP) | `./lab.sh update-ip` (the boot service normally does this) | |
| Grafana panels show "No data" | Check the time range (last 15 minutes), then `./lab.sh preflight` | Prometheus at `prometheus.<domain>` |
| `chaos bank-lambat` fails with "no netem module" | `./lab.sh bank slow` | Backup video 4 |
| Telegram message does not arrive | Show Alertmanager's alert list on *RelNusa 2* instead | Mention it and move on; the alert is visible in Grafana |
| A node shows *NotReady* after the VM was stopped and started | `./lab.sh restart` (about 2 minutes) | |
| A demo leaves the lab in a strange state | `./lab.sh reset`, `./lab.sh release undo`, `./lab.sh chaos stop` | `./lab.sh rebuild` takes about 3 minutes |
| VM unreachable | Backup videos for every demo | |

## After the talk

```bash
./lab.sh traffic stop
./lab.sh down               # optional: deletes the cluster; the VM can be reused
```

Then, in AWS: stop or terminate the VM, and delete any IAM user or access key created for the lab. In Telegram: revoke the bot token with @BotFather if it was shared outside your team.
