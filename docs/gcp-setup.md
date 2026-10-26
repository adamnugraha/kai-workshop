# Running the lab on Google Cloud (Jakarta region)

About 10 minutes in the console, then 15 to 25 minutes of automatic install. Other platforms: [AWS](aws-setup.md), [your own server](server-setup.md). Alerts: [Telegram](telegram-setup.md).

## 1. Create the VM

The quickest way is **Cloud Shell** (the `>_` icon at the top of the console), which already has `gcloud`. Pick or create a project with billing enabled, then paste:

```bash
cat > startup.sh <<'EOF'
#!/bin/bash
# Runs at every boot; installs the lab only the first time.
[ -f /var/lib/kai-workshop-installed ] && exit 0
curl -fsSL https://raw.githubusercontent.com/adamnugraha/kai-workshop/main/bootstrap.sh | bash \
  && touch /var/lib/kai-workshop-installed
EOF

gcloud services enable compute.googleapis.com
gcloud compute instances create kai-lab \
  --zone=asia-southeast2-a \
  --machine-type=e2-standard-8 \
  --image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud \
  --boot-disk-size=100GB --boot-disk-type=pd-balanced \
  --metadata-from-file=startup-script=startup.sh
```

The same in the console: Compute Engine → VM instances → **Create instance**:

| Setting | Value |
|---|---|
| Name | `kai-lab` |
| Region / zone | `asia-southeast2` (Jakarta) / `asia-southeast2-a` |
| Machine type | `e2-standard-8` (8 vCPU, 32 GB). `n2-standard-8` gives steadier CPU for the load tests |
| Boot disk | Ubuntu 24.04 LTS (x86/64), balanced persistent disk, 100 GB |
| Firewall | nothing to tick; SSH is allowed by the default network |
| Advanced → Management → Automation → Startup script | the content of `startup.sh` above |

## 2. Watch the install

Open the VM with the **SSH** button in the console (a browser terminal), then:

```bash
sudo tail -f /var/log/relnusa-lab-install.log     # ends with "done"
cd /opt/kai-workshop && ./lab.sh preflight
```

`./lab.sh` switches to root by itself, so your own user is fine.

## 3. Open the dashboards from your laptop

The browser SSH window cannot forward ports, so the laptop needs a normal SSH connection. Two ways:

**With an SSH key (no extra software on Windows 10/11, macOS or Linux):**

```bash
ssh-keygen -t ed25519 -f ~/.ssh/kai-lab -C presenter     # once, on the laptop
```

Copy the content of `~/.ssh/kai-lab.pub`, then in the console: VM instance → **Edit** → Security and access → **SSH keys** → Add item → paste → Save. The user name is the last word of the key (`presenter`). Then:

```bash
ssh -i ~/.ssh/kai-lab -N -L 8080:127.0.0.1:80 -L 9090:127.0.0.1:9090 presenter@EXTERNAL_IP
```

**With the gcloud CLI on the laptop:**

```bash
gcloud compute ssh kai-lab --zone asia-southeast2-a -- -N -L 8080:127.0.0.1:80 -L 9090:127.0.0.1:9090
```

Keep the window open and use Chrome or Edge: `http://grafana.localhost:8080`, `http://app.localhost:8080`, `http://legacy.localhost:8080`. The Grafana password is shown by `./lab.sh info`.

## 4. At the venue

If the venue's network blocks port 22, `gcloud` can tunnel SSH over HTTPS through Google's Identity-Aware Proxy. Allow it once (Cloud Shell):

```bash
gcloud compute firewall-rules create allow-ssh-from-iap \
  --network=default --direction=INGRESS --allow=tcp:22 --source-ranges=35.235.240.0/20
```

Then on the laptop:

```bash
gcloud compute ssh kai-lab --zone asia-southeast2-a --tunnel-through-iap -- -N -L 8080:127.0.0.1:80 -L 9090:127.0.0.1:9090
```

A phone hotspot is the other fallback.

## 5. Cost and stopping

Check the current price for your machine type in asia-southeast2 on the Compute Engine pricing page or the Google Cloud pricing calculator. Stop the VM when you are not rehearsing (`gcloud compute instances stop kai-lab --zone asia-southeast2-a`); the disk is still billed. The lab comes back by itself after a start. The external IP changes after a stop unless you reserve a static address.

## 6. After the talk

```bash
gcloud compute instances delete kai-lab --zone asia-southeast2-a
gcloud compute firewall-rules delete allow-ssh-from-iap     # if you created it
```

Remove the SSH key from the instance or project metadata if you added one there.
