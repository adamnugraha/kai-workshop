# Installing and opening the lab

Everything on this page runs on one Linux VM. For a step-by-step walk through a specific place, use the guides for [AWS](aws-setup.md), [Google Cloud](gcp-setup.md) or [your own server](server-setup.md); for alerts on phones, set up [Telegram](telegram-setup.md).

## What you need

- One Ubuntu 22.04 or 24.04 VM with 8 vCPUs, 32 GB of RAM and a 100 GB disk (at least 4 vCPUs and 16 GB for the `small` profile)
- Outbound internet access to Docker Hub, GitHub, ghcr.io, quay.io and registry.k8s.io
- Inbound access: SSH, plus TCP 80 and 443 when the lab is opened on the public IP (`public` mode, the default for cloud VMs)
- Ports 80 and 443 (and 9090 on 127.0.0.1) must be free; if 80 or 9090 is already in use, change `HTTP_PORT` and `PROM_PORT` in `lab.env` before installing (HTTPS is only enabled when the lab uses port 80)

## Install in one go

On a new VM (the same line also works as *user data* on AWS or as a *startup script* on Google Cloud):

```bash
curl -fsSL https://raw.githubusercontent.com/adamnugraha/kai-workshop/main/bootstrap.sh | sudo bash
```

## Install step by step

```bash
git clone https://github.com/adamnugraha/kai-workshop.git
cd kai-workshop
cp lab.env.example lab.env     # choose LAB_ACCESS, the Telegram token, the small profile
sudo ./lab.sh install-deps     # Docker, k3d, kubectl, helm, kubectl plugins
./lab.sh up                    # 15 to 25 minutes on the first install
./lab.sh info                  # addresses and the password
```

Every setting is explained in [`lab.env.example`](../lab.env.example). After changing `lab.env` on a running lab, run `./lab.sh apply`.

## Open the lab

There are two modes, chosen with `LAB_ACCESS` in `lab.env` before `./lab.sh up`.

**`public` mode** (the default when installing with `bootstrap.sh`): every address uses the VM's public IP through the free DNS service [sslip.io](https://sslip.io), so there is no DNS or SSH tunnel to set up. The lab requests free HTTPS certificates from Let's Encrypt for every address, so `https://` works right away; `http://` keeps working too. Open TCP 80 and 443 in the firewall (Let's Encrypt checks every name over port 80).

| Address | Contents | Login |
|---|---|---|
| `https://legacy.<ip>.sslip.io` | Legacy system site | Not needed |
| `https://app.<ip>.sslip.io` | Modern system site | Not needed |
| `https://grafana.<ip>.sslip.io` | Dashboards | View without logging in; edit as `admin` |
| `https://jaeger.<ip>.sslip.io`, `chaos.`, `rollouts.`, `prometheus.`, `alertmanager.` | Operator tools | `admin` and the password from `./lab.sh info` |

`./lab.sh info` shows the exact addresses. If the certificates have not been issued yet (for example because port 80 or 443 is still closed), `./lab.sh info` shows `http://` addresses and `./lab.sh preflight` explains why. To turn HTTPS off, set `LAB_HTTPS=off` in `lab.env` and run `./lab.sh apply`.

If the IP changes after the VM is stopped and started, these names follow it automatically, certificates included. For fixed addresses, use an Elastic IP (AWS), a static IP (Google Cloud) or your own domain through `LAB_DOMAIN`.

**`tunnel` mode**: everything listens only on 127.0.0.1 on the VM, which suits servers without a public IP. From your laptop:

```bash
ssh -N -L 8080:127.0.0.1:80 ubuntu@VM-ADDRESS
```

Then open `http://app.localhost:8080`, `http://grafana.localhost:8080` and so on in Chrome or Edge (both resolve `*.localhost` without any DNS setup).

## Keep it up to date

To update an installed lab to the latest version of this repository (data and releases are kept):

```bash
./lab.sh update
```

Older copies that do not have the `update` command yet only need to run `sudo git pull && ./lab.sh apply` once.

## Before and between sessions

| To | Run |
|---|---|
| Check everything at once before going on stage | `./lab.sh preflight` |
| See nodes, pods, the database primary, traffic and the bank's mode | `./lab.sh status` |
| Clear bookings, refill seats and put the bank back to normal | `./lab.sh reset` |
| Start or stop the background traffic on both sites | `./lab.sh traffic start` or `./lab.sh traffic stop` |
| Restart the cluster in order after a reboot | `./lab.sh restart` |
| Delete the cluster | `./lab.sh down` |

## Certificates and safety

- The lab is built for training. In `public` mode the addresses use HTTPS with Let's Encrypt certificates and plain HTTP stays available; the operator tools sit behind a simple login, and the lab holds no real data. Delete the VM after the event.
- Every time the cluster is recreated (`./lab.sh down`, then `./lab.sh up`), the lab requests new certificates. Let's Encrypt issues only five certificates per week for the same set of names, so do not recreate the cluster more often than that; `./lab.sh restart`, `./lab.sh apply` and `./lab.sh update` reuse the existing certificates.
- Performance figures in the lab depend on the VM size and cannot be compared directly with any production system.
