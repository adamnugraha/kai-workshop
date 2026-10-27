# Running the lab on your own server

Any Linux machine works if it meets the checks below: a VPS, a VM in your data centre, VMware, Proxmox or a bare-metal box. Cloud guides: [AWS](aws-setup.md), [GCP](gcp-setup.md). Alerts: [Telegram](telegram-setup.md).

## 1. Check the machine first

Run these on the server:

```bash
lsb_release -ds                 # Ubuntu 22.04 or 24.04 (Debian 12 also works)
nproc; free -g; df -h /var      # 8 CPUs, 32 GB RAM, 100 GB free (small profile: 4 CPUs, 16 GB)
systemd-detect-virt             # kvm, vmware, microsoft, xen or none are fine; lxc or openvz are not
sudo modprobe sch_netem && echo netem-ok      # needed for the Chaos Mesh network delay demo
sudo ss -ltnp '( sport = :80 or sport = :443 or sport = :9090 )'   # should list no process under the header
curl -sI https://registry-1.docker.io/v2/ | head -1   # any HTTP status line (401 is fine) means outbound internet works
curl -s https://checkip.amazonaws.com    # the public IP the internet sees for this server
```

| If | Then |
|---|---|
| It is an LXC or OpenVZ container | Use a full VM; Kubernetes in Docker does not run reliably inside those containers |
| `sch_netem` cannot be loaded | Everything works, but use `./lab.sh bank slow` instead of `./lab.sh chaos bank-lambat` in demo 4 |
| Port 80 or 9090 is already in use (for example your own Prometheus) | Set `HTTP_PORT` and `PROM_PORT` in `lab.env` before installing (step 3). HTTPS needs port 80, so it stays off when `HTTP_PORT` is something else |
| Port 443 is already in use | Everything works over plain HTTP; set `LAB_HTTPS=off` in `lab.env` to skip HTTPS |
| The server also runs production workloads | Prefer a separate VM. The lab starts about 40 containers and the load tests use all CPUs for a few minutes |

## 2. Choose how people reach it

| `LAB_ACCESS` | When | Addresses |
|---|---|---|
| `public` (default) | The server has a public IP that the internet can reach on ports 80 and 443, like most VPSs | `https://app.<ip>.sslip.io` and so on, from any browser (`http://` works too) |
| `tunnel` | The server sits behind NAT or in an office network | Everything on 127.0.0.1, opened from the laptop over an SSH tunnel |

[sslip.io](https://sslip.io) is a free DNS service that answers any `<name>.<ip>.sslip.io` with that IP. With your own domain, point a wildcard record such as `*.lab.example.com` at the server and set `LAB_DOMAIN=lab.example.com`.

In public mode the lab asks Let's Encrypt for a free certificate for each address. Let's Encrypt checks every name over port 80 first, so port 80 must be open even if people only use `https://`. Ports 80 and 443 are published by Docker, which bypasses `ufw`; your provider's firewall or security group is what must allow TCP 80 and 443. The demo sites and Grafana's read-only view are open to anyone with the address; the operator tools ask for a password.

## 3. Install

```bash
git clone https://github.com/adamnugraha/kai-workshop.git
cd kai-workshop
cp lab.env.example lab.env
nano lab.env                    # LAB_ACCESS, ports, Telegram, LAB_PROFILE=small for 4 CPU / 16 GB
sudo ./lab.sh install-deps      # Docker, k3d, kubectl, helm and plugins
./lab.sh up                     # 15 to 25 minutes the first time
./lab.sh preflight              # must end with "ready"
./lab.sh info                   # the addresses and the password
```

`./lab.sh` switches to root by itself (it asks for your sudo password if needed). If the detected public IP is wrong (for example behind a provider's NAT), set `LAB_PUBLIC_IP` in `lab.env` and run `./lab.sh update-ip`. Behind a corporate proxy that re-signs TLS, point `LAB_EXTRA_CA` in `lab.env` at the proxy's CA bundle.

Later changes to this repository reach an installed lab with `./lab.sh update`, which pulls the code and re-applies it without touching the data (a copy older than that command needs `git pull && ./lab.sh apply` once). After editing `lab.env`, run `./lab.sh apply`.

## 4. Tunnel mode only: reach it from the laptop

```bash
ssh -N -L 8080:127.0.0.1:80 YOUR_USER@SERVER_ADDRESS
```

If you changed `HTTP_PORT`, use it on the right-hand side (for example `-L 8080:127.0.0.1:8081`). Then browse to `http://grafana.localhost:8080` in Chrome or Edge. A server inside your office network needs your VPN or an SSH port reachable from the venue; test that path from outside the office before the day.

## 5. Removing it

```bash
./lab.sh down                   # deletes the cluster and its containers
sudo systemctl disable relnusa-lab.service
```

Docker and the tools stay installed. The kernel settings the installer adds are in `/etc/sysctl.d/99-relnusa-lab.conf` and `/etc/modules-load.d/relnusa-lab.conf`; delete them if you do not want them.
