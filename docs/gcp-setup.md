# Running the lab on Google Cloud (Jakarta region)

About 10 minutes in Cloud Shell, then 15 to 25 minutes of automatic install. Other platforms: [AWS](aws-setup.md), [your own server](server-setup.md). Alerts: [Telegram](telegram-setup.md).

By default the lab opens at the VM's external IP, for example `http://app.203.0.113.10.sslip.io`, with no SSH tunnel. [sslip.io](https://sslip.io) is a free DNS service that answers any `<name>.<ip>.sslip.io` with that IP, so there is no DNS to set up.

## 1. Create the VM

Open **Cloud Shell** (the `>_` icon at the top of the console), pick or create a project with billing enabled, then paste:

```bash
cat > startup.sh <<'EOF'
#!/bin/bash
# Runs at every boot; installs the lab only the first time.
[ -f /var/lib/kai-workshop-installed ] && exit 0
curl -fsSL https://raw.githubusercontent.com/adamnugraha/kai-workshop/main/bootstrap.sh | bash \
  && touch /var/lib/kai-workshop-installed
EOF

gcloud services enable compute.googleapis.com

# A fixed external address, so the lab's addresses survive a stop and start
gcloud compute addresses create kai-lab-ip --region=asia-southeast2

# Let browsers reach the lab on port 80
gcloud compute firewall-rules create kai-lab-http --network=default \
  --direction=INGRESS --allow=tcp:80 --source-ranges=0.0.0.0/0 --target-tags=kai-lab

gcloud compute instances create kai-lab \
  --zone=asia-southeast2-a \
  --machine-type=e2-standard-8 \
  --image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud \
  --boot-disk-size=100GB --boot-disk-type=pd-balanced \
  --address=kai-lab-ip --tags=kai-lab \
  --metadata-from-file=startup-script=startup.sh
```

To keep everything on 127.0.0.1 and use an SSH tunnel instead, add `export LAB_ACCESS=tunnel` on the line before `curl` in `startup.sh` (and skip the firewall rule). Telegram settings can be passed the same way (`export TELEGRAM_BOT_TOKEN=...`, `export TELEGRAM_CHAT_ID=...`).

`n2-standard-8` instead of `e2-standard-8` gives steadier CPU for the load tests.

## 2. Check the install

About 25 minutes later, open the VM with the **SSH** button in the console (a terminal in the browser), then:

```bash
sudo tail -f /var/log/relnusa-lab-install.log     # ends with "done"
cd /opt/kai-workshop
./lab.sh preflight                                # must end with "ready"
./lab.sh info                                     # the addresses and the password
```

`./lab.sh` switches to root by itself, so your own user is fine.

## 3. Open the lab

Open the addresses from `./lab.sh info` in any browser, including a phone:

| Address | What | Login |
|---|---|---|
| `http://app.<ip>.sslip.io` | Modern site | none |
| `http://legacy.<ip>.sslip.io` | Legacy site | none |
| `http://grafana.<ip>.sslip.io` | Dashboards | view without login; `admin` to edit |
| `http://jaeger.`, `chaos.`, `rollouts.`, `prometheus.`, `alertmanager.<ip>.sslip.io` | Operator tools | `admin` and the password from `./lab.sh info` |

Run the demo commands in the console's browser SSH window. It works over HTTPS, so a venue that blocks port 22 is no problem.

## 4. At the venue

- **The sslip.io names do not resolve:** a few corporate DNS filters block wildcard DNS services. Use your phone hotspot, or set your own domain: point a wildcard record `*.lab.example.com` at the static address, put `LAB_DOMAIN=lab.example.com` in `lab.env`, and run `./lab.sh update-ip`.
- **Test it the day before** from a network other than your office, ideally from your phone on mobile data.

## 5. Cost and stopping

Check the current price for your machine type in asia-southeast2 on the Compute Engine pricing page or the Google Cloud pricing calculator; the static address is billed too. Stop the VM when you are not rehearsing (`gcloud compute instances stop kai-lab --zone asia-southeast2-a`); the disk is still billed. After a start, a boot service brings the cluster back. Give it about five minutes, then run `./lab.sh preflight` (if a node still shows as not ready, run `./lab.sh restart`).

## 6. After the talk

```bash
gcloud compute instances delete kai-lab --zone asia-southeast2-a
gcloud compute addresses delete kai-lab-ip --region asia-southeast2
gcloud compute firewall-rules delete kai-lab-http
```
