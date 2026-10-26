# Running the lab on your own server

Any Linux machine works if it meets the checks below: a VM in your data centre, VMware, Proxmox, a bare-metal box, or a VPS. Cloud guides: [AWS](aws-setup.md), [GCP](gcp-setup.md). Alerts: [Telegram](telegram-setup.md).

## 1. Check the machine first

Run these on the server:

```bash
lsb_release -ds                 # Ubuntu 22.04 or 24.04 (Debian 12 also works)
nproc; free -g; df -h /var      # 8 CPUs, 32 GB RAM, 100 GB free (small profile: 4 CPUs, 16 GB)
systemd-detect-virt             # kvm, vmware, microsoft, xen or none are fine; lxc or openvz are not
sudo modprobe sch_netem && echo netem-ok      # needed for the Chaos Mesh network delay demo
sudo ss -ltnp '( sport = :80 or sport = :9090 )'   # should list no process under the header
curl -sI https://registry-1.docker.io/v2/ | head -1   # any HTTP status line (401 is fine) means outbound internet works
```

| If | Then |
|---|---|
| It is an LXC or OpenVZ container | Use a full VM; Kubernetes in Docker does not run reliably inside those containers |
| `sch_netem` cannot be loaded | Everything works, but use `./lab.sh bank slow` instead of `./lab.sh chaos bank-lambat` in demo 4 |
| Port 80 or 9090 is already in use (for example your own Prometheus) | Set `HTTP_PORT` and `PROM_PORT` in `lab.env` before installing (step 2) |
| The server also runs production workloads | Prefer a separate VM. The lab starts about 40 containers and the load tests use all CPUs for a few minutes |

## 2. Install

```bash
git clone https://github.com/adamnugraha/kai-workshop.git
cd kai-workshop
cp lab.env.example lab.env
nano lab.env                    # optional: ports, Telegram, LAB_PROFILE=small for 4 CPU / 16 GB
sudo ./lab.sh install-deps      # Docker, k3d, kubectl, helm and plugins
./lab.sh up                     # 15 to 25 minutes the first time
./lab.sh preflight
```

`./lab.sh` switches to root by itself (it asks for your sudo password if needed). Behind a corporate proxy that re-signs TLS, point `LAB_EXTRA_CA` in `lab.env` at the proxy's CA bundle.

## 3. Reach it from the laptop

The web interfaces only listen on 127.0.0.1 of the server, so open an SSH tunnel:

```bash
ssh -N -L 8080:127.0.0.1:80 -L 9090:127.0.0.1:9090 YOUR_USER@SERVER_ADDRESS
```

If you changed the ports, use them on the right-hand side (for example `-L 8080:127.0.0.1:8081`). Then browse to `http://grafana.localhost:8080` in Chrome or Edge.

Plan how you will reach the server from the venue: a server inside your office network needs your VPN, or an SSH port reachable from the internet. Test that path from outside the office before the day.

## 4. Removing it

```bash
./lab.sh down                   # deletes the cluster and its containers
```

Docker and the tools stay installed. The kernel settings the installer adds are in `/etc/sysctl.d/99-relnusa-lab.conf` and `/etc/modules-load.d/relnusa-lab.conf`; delete them if you do not want them.
