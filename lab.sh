#!/usr/bin/env bash
# RelNusa availability lab: one command to build, run and demo everything.
# Run "./lab.sh help" for the list of commands.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Everything runs as root, so the cluster, its kubeconfig and the state folder
# always belong to the same user, whoever installed it and whoever presents.
if [ "$(id -u)" -ne 0 ]; then exec sudo -E bash "$ROOT/lab.sh" "$@"; fi
# sudo -E keeps the caller's HOME and KUBECONFIG; always use root's, so the
# commands reach the lab cluster and never a cluster from someone's own config.
HOME="$(getent passwd root | cut -d: -f6)"; HOME="${HOME:-/root}"
export HOME KUBECONFIG="$HOME/.kube/config"
STATE="$ROOT/.lab"
mkdir -p "$STATE"
# Optional settings file (copy lab.env.example to lab.env).
if [ -f "$ROOT/lab.env" ]; then set -a; . "$ROOT/lab.env"; set +a; fi

CLUSTER="${CLUSTER:-relnusa}"
# How people reach the lab:
#   public  https://app.<public-ip>.sslip.io and so on (http:// works too);
#           ports 80 and 443 are open to the internet and the operator tools
#           ask for a login
#   tunnel  everything stays on 127.0.0.1 and is opened over an SSH tunnel
LAB_ACCESS="${LAB_ACCESS:-tunnel}"
case "$LAB_ACCESS" in public|tunnel) ;; *) echo "LAB_ACCESS must be public or tunnel" >&2; exit 1;; esac
if [ "$LAB_ACCESS" = public ]; then LAB_BIND=0.0.0.0; else LAB_BIND=127.0.0.1; fi
# Optional: your own wildcard DNS name (*.lab.example.com -> this machine)
# instead of <ip>.sslip.io, and an override for the detected public IP.
LAB_DOMAIN_FIXED="${LAB_DOMAIN:-}"
LAB_DNS_SUFFIX="${LAB_DNS_SUFFIX:-sslip.io}"
LAB_PROFILE="${LAB_PROFILE:-full}"
K3S_IMAGE="${K3S_IMAGE:-rancher/k3s:v1.36.5-k3s1}"
K6_IMAGE="${K6_IMAGE:-grafana/k6:1.8.1}"
K3D_VERSION="${K3D_VERSION:-v5.8.3}"
KUBECTL_VERSION="${KUBECTL_VERSION:-v1.36.5}"
HELM_VERSION="${HELM_VERSION:-v3.22.1}"
ROLLOUTS_PLUGIN_VERSION="${ROLLOUTS_PLUGIN_VERSION:-v1.10.0}"
CNPG_PLUGIN_VERSION="${CNPG_PLUGIN_VERSION:-1.30.1}"
KPS_CHART_VERSION="${KPS_CHART_VERSION:-91.9.0}"
CNPG_CHART_VERSION="${CNPG_CHART_VERSION:-0.29.1}"
ROLLOUTS_CHART_VERSION="${ROLLOUTS_CHART_VERSION:-2.43.2}"
CHAOS_CHART_VERSION="${CHAOS_CHART_VERSION:-2.8.4}"
TRAFFIC_RATE="${TRAFFIC_RATE:-4}"
# Host ports (change them if the server already uses 80 or 9090; they are
# fixed when the cluster is created). Prometheus always stays on 127.0.0.1.
HTTP_PORT="${HTTP_PORT:-80}"
PROM_PORT="${PROM_PORT:-9090}"
# HTTPS with free Let's Encrypt certificates. auto turns it on in public mode
# on port 80, because Let's Encrypt checks each host name over port 80.
LAB_HTTPS="${LAB_HTTPS:-auto}"
case "$LAB_HTTPS" in
  auto) if [ "$LAB_ACCESS" = public ] && [ "$HTTP_PORT" = 80 ]; then LAB_HTTPS=on; else LAB_HTTPS=off; fi;;
  off) ;;
  *) echo "LAB_HTTPS must be auto or off" >&2; exit 1;;
esac
# Optional contact address for Let's Encrypt, and the ACME server (the
# Let's Encrypt staging server or a test CA can be set here for testing).
LAB_ACME_EMAIL="${LAB_ACME_EMAIL:-}"
LAB_ACME_CA="${LAB_ACME_CA:-https://acme-v02.api.letsencrypt.org/directory}"
DOCKER_BUILD_FLAGS="${DOCKER_BUILD_FLAGS:-}"

if [ "$LAB_PROFILE" = "small" ]; then DB_INSTANCES="${DB_INSTANCES:-2}"; else DB_INSTANCES="${DB_INSTANCES:-3}"; fi
if [ "$DB_INSTANCES" -gt 1 ]; then SEARCH_DB_HOST=relnusa-db-ro; else SEARCH_DB_HOST=relnusa-db-rw; fi

c_info() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
c_ok()   { printf '\033[1;32m ok\033[0m %s\n' "$*"; }
c_warn() { printf '\033[1;33m !!\033[0m %s\n' "$*"; }
die()    { printf '\033[1;31mERROR\033[0m %s\n' "$*" >&2; exit 1; }
need()   { command -v "$1" >/dev/null 2>&1 || die "'$1' is not installed. Run: sudo ./lab.sh install-deps"; }

arch() { case "$(uname -m)" in x86_64|amd64) echo amd64;; aarch64|arm64) echo arm64;; *) die "unsupported CPU $(uname -m)";; esac; }

# ---------------------------------------------------------------- access
public_ip() {
  # This machine's public IPv4: cloud metadata first, then an echo service.
  local ip="${LAB_PUBLIC_IP:-}" tok
  if [ -z "$ip" ]; then   # AWS (IMDSv2)
    tok="$(curl -fsS -m 2 -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' http://169.254.169.254/latest/api/token 2>/dev/null || true)"
    if [ -n "$tok" ]; then ip="$(curl -fsS -m 2 -H "X-aws-ec2-metadata-token: $tok" http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || true)"; fi
  fi
  if [ -z "$ip" ]; then   # Google Cloud
    ip="$(curl -fsS -m 2 -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip 2>/dev/null || true)"
  fi
  if [ -z "$ip" ]; then   # any other server
    ip="$(curl -fsS -m 5 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]' || true)"
  fi
  [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
  echo "$ip"
}

desired_domain() {
  # The domain the lab should use now, from lab.env and the current public IP.
  if [ -n "$LAB_DOMAIN_FIXED" ]; then echo "$LAB_DOMAIN_FIXED"
  elif [ "$LAB_ACCESS" = public ]; then
    local ip; ip="$(public_ip)" || die "could not find this machine's public IP; set LAB_PUBLIC_IP (or LAB_DOMAIN) in lab.env"
    echo "$ip.$LAB_DNS_SUFFIX"
  else echo localhost
  fi
}

# Commands use the domain the cluster was set up with ("./lab.sh update-ip"
# applies a new one). Before the first install it is worked out from lab.env.
LAB_DOMAIN=""
ensure_domain() {
  [ -n "$LAB_DOMAIN" ] && return 0
  if [ -s "$STATE/applied-domain" ]; then LAB_DOMAIN="$(cat "$STATE/applied-domain")"; else LAB_DOMAIN="$(desired_domain)"; fi
}

site_port() {
  # The port people type in the browser: the tunnel's 8080, or HTTP_PORT.
  if [ "$LAB_ACCESS" = tunnel ]; then echo ":8080"; elif [ "$HTTP_PORT" != 80 ]; then echo ":$HTTP_PORT"; fi
}
# http, or https once the certificates are trusted (detect_scheme sets it).
URL_SCHEME=http
site_url() { echo "$URL_SCHEME://$1.$LAB_DOMAIN$(site_port)"; }
https_on() {
  # HTTPS needs host names that Let's Encrypt can reach from the internet, so
  # not the sslip.io names of a private address (a VM on an office network).
  [ "$LAB_HTTPS" = on ] || return 1
  case "$LAB_DOMAIN" in
    10.*|127.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*|100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*) return 1;;
  esac
}
https_valid() {
  # True when https://<site>.<domain> on this machine presents a certificate
  # that browsers trust, checked against the system's CA list.
  https_on || return 1
  curl -sS -m 5 --noproxy '*' -o /dev/null --resolve "${1:-app}.$LAB_DOMAIN:443:127.0.0.1" "https://${1:-app}.$LAB_DOMAIN/" 2>/dev/null
}
detect_scheme() { if https_valid app; then URL_SCHEME=https; else URL_SCHEME=http; fi; }
lab_curl() { curl -fsS -u "admin:$(grafana_password)" -H "Host: $1.$LAB_DOMAIN" "${@:3}" "http://127.0.0.1:$HTTP_PORT$2"; }

grafana_password() {
  if [ -n "${GRAFANA_PASSWORD:-}" ]; then echo "$GRAFANA_PASSWORD"; return; fi
  if [ ! -s "$STATE/grafana-password" ]; then
    head -c 96 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-16 > "$STATE/grafana-password"
    chmod 600 "$STATE/grafana-password"
  fi
  cat "$STATE/grafana-password"
}

image_ref() {
  local tag
  tag="$(cd "$ROOT/app" && find . -type f \( -name '*.go' -o -name '*.html' -o -name 'go.*' -o -name Dockerfile \) -print0 | sort -z | xargs -0 sha1sum | sha1sum | cut -c1-10)"
  echo "relnusa/app:$tag"
}

render() {
  # render FILE [APP_VERSION] [FAULT_ERROR_RATE]
  sed -e "s|__IMAGE__|$(cat "$STATE/image")|g" \
      -e "s|__LAB_DOMAIN__|$LAB_DOMAIN|g" \
      -e "s|__URL_PORT__|$(site_port)|g" \
      -e "s|__DB_INSTANCES__|$DB_INSTANCES|g" \
      -e "s|__SEARCH_DB_HOST__|$SEARCH_DB_HOST|g" \
      -e "s|__APP_VERSION__|${2:-v1}|g" \
      -e "s|__FAULT_ERROR_RATE__|${3:-0}|g" \
      -e "s|__GRAFANA_PASSWORD__|$(grafana_password)|g" \
      "$1"
}

# ---------------------------------------------------------------- install-deps
cmd_install_deps() {
  [ "$(id -u)" -eq 0 ] || die "run as root: sudo ./lab.sh install-deps"
  local a; a="$(arch)"
  c_info "Base packages"
  if command -v apt-get >/dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    # A fresh VM may still be running its own package updates: wait for the
    # package lock instead of failing (the Docker installer uses apt too).
    echo 'DPkg::Lock::Timeout "900";' >/etc/apt/apt.conf.d/99-relnusa-lock-wait
    local n
    for n in 1 2 3 4 5; do apt-get update -q && break; c_warn "apt-get update failed (attempt $n of 5); retrying in 20 s"; sleep 20; done
    apt-get install -y -q curl ca-certificates git jq tar gzip openssl >/dev/null
    apt-get install -y -q "linux-modules-extra-$(uname -r)" >/dev/null 2>&1 || c_warn "linux-modules-extra not available (network fault injection may be limited)"
  fi
  if ! command -v docker >/dev/null; then
    c_info "Docker"
    curl -fsSL https://get.docker.com | sh
  fi
  systemctl enable --now docker >/dev/null 2>&1 || true
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then usermod -aG docker "$SUDO_USER" || true; fi

  c_info "Kernel settings for many containers and network fault injection"
  cat >/etc/sysctl.d/99-relnusa-lab.conf <<'EOF'
# Containers reach the internet only while the kernel forwards packets.
# Google Cloud's Ubuntu image turns forwarding off in
# 60-gce-network-security.conf; this file is read after it.
net.ipv4.ip_forward = 1
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288
net.core.somaxconn = 4096
net.ipv4.ip_local_port_range = 10240 65000
EOF
  sysctl --system >/dev/null || true
  printf 'br_netfilter\noverlay\nsch_netem\n' >/etc/modules-load.d/relnusa-lab.conf
  for m in br_netfilter overlay sch_netem; do modprobe "$m" 2>/dev/null || c_warn "kernel module $m not loaded"; done

  c_info "k3d $K3D_VERSION, kubectl $KUBECTL_VERSION, helm $HELM_VERSION"
  curl -fsSL -o /usr/local/bin/k3d "https://github.com/k3d-io/k3d/releases/download/$K3D_VERSION/k3d-linux-$a"
  curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/$a/kubectl"
  curl -fsSL "https://get.helm.sh/helm-$HELM_VERSION-linux-$a.tar.gz" | tar xz -C /tmp "linux-$a/helm"
  mv "/tmp/linux-$a/helm" /usr/local/bin/helm
  c_info "kubectl plugins (Argo Rollouts, CloudNativePG)"
  curl -fsSL -o /usr/local/bin/kubectl-argo-rollouts "https://github.com/argoproj/argo-rollouts/releases/download/$ROLLOUTS_PLUGIN_VERSION/kubectl-argo-rollouts-linux-$a"
  local cnpg_arch; cnpg_arch=$([ "$a" = amd64 ] && echo x86_64 || echo arm64)
  curl -fsSL "https://github.com/cloudnative-pg/cloudnative-pg/releases/download/v$CNPG_PLUGIN_VERSION/kubectl-cnpg_${CNPG_PLUGIN_VERSION}_linux_${cnpg_arch}.tar.gz" | tar xz -C /usr/local/bin kubectl-cnpg
  chmod +x /usr/local/bin/k3d /usr/local/bin/kubectl /usr/local/bin/helm /usr/local/bin/kubectl-argo-rollouts /usr/local/bin/kubectl-cnpg
  c_ok "dependencies installed"
}

# ---------------------------------------------------------------- cluster
write_k3d_config() {
  cat >"$STATE/k3d.yaml" <<EOF
apiVersion: k3d.io/v1alpha5
kind: Simple
metadata:
  name: $CLUSTER
servers: 1
agents: 2
image: $K3S_IMAGE
kubeAPI:
  # The Kubernetes API stays on this machine only, also in public mode.
  hostIP: "127.0.0.1"
  hostPort: "6550"
ports:
  - port: $LAB_BIND:$HTTP_PORT:80
    nodeFilters: [server:0:direct]
  - port: 127.0.0.1:$PROM_PORT:30090
    nodeFilters: [server:0:direct]
$(https_port_yaml)
options:
  k3d:
    wait: true
    timeout: "300s"
  k3s:
    extraArgs:
      - arg: --kube-controller-manager-arg=node-monitor-grace-period=20s
        nodeFilters: [server:*]
      # The lab uses no NetworkPolicies. Without this, an agent whose container
      # IP changed after a VM reboot can fail to start its policy controller.
      - arg: --disable-network-policy
        nodeFilters: [server:*]
    nodeLabels:
      - label: topology.kubernetes.io/zone=zone-a
        nodeFilters: [server:0]
      - label: topology.kubernetes.io/zone=zone-b
        nodeFilters: [agent:0]
      - label: lab.relnusa.io/legacy=true
        nodeFilters: [agent:0]
      - label: topology.kubernetes.io/zone=zone-c
        nodeFilters: [agent:1]
  kubeconfig:
    updateDefaultKubeconfig: true
    switchCurrentContext: true
EOF
  if [ ! -f /sys/fs/cgroup/cgroup.controllers ]; then
    # Older hosts still on cgroup v1: newer kubelets refuse to start there
    # unless told otherwise. Ubuntu 22.04+ and RHEL 9 use cgroup v2.
    c_warn "host uses cgroup v1; allowing it for the kubelet"
    sed -i 's|^    nodeLabels:|      - arg: --kubelet-arg=fail-cgroupv1=false\n        nodeFilters: [all]\n    nodeLabels:|' "$STATE/k3d.yaml"
  fi
  local free_pct; free_pct="$(df --output=avail,size -k / | tail -1 | awk '{printf "%d", $1*100/$2}')"
  if [ "${LAB_RELAXED_EVICTION:-auto}" = yes ] || { [ "${LAB_RELAXED_EVICTION:-auto}" = auto ] && [ "$free_pct" -lt 20 ]; }; then
    # The kubelet evicts pods when free space drops below ~10-15% of the
    # disk's size. On shared or quota-limited volumes that happens even with
    # plenty of real space left.
    c_warn "only ${free_pct}% of the disk is free; relaxing kubelet disk eviction thresholds"
    sed -i 's|^    nodeLabels:|      - arg: --kubelet-arg=eviction-hard=imagefs.available<1%,nodefs.available<1%\n        nodeFilters: [all]\n      - arg: --kubelet-arg=image-gc-high-threshold=99\n        nodeFilters: [all]\n      - arg: --kubelet-arg=image-gc-low-threshold=98\n        nodeFilters: [all]\n    nodeLabels:|' "$STATE/k3d.yaml"
  fi
  local volumes=""
  if [ -n "${LAB_EXTRA_CA:-}" ]; then
    # Corporate proxies that re-sign TLS: trust their CA inside the nodes.
    volumes+="  - volume: $LAB_EXTRA_CA:/etc/ssl/certs/ca-certificates.crt
    nodeFilters: [all]
"
  fi
  local capeff; capeff="$(awk '/^CapEff/{print $2}' /proc/self/status)"
  if [ $(( (16#$capeff >> 24) & 1 )) -eq 0 ]; then
    # Some sandboxes drop CAP_SYS_RESOURCE, so nested containers cannot
    # lower their OOM score. Tell containerd to clamp instead of failing.
    c_warn "host lacks CAP_SYS_RESOURCE; restricting OOM score changes in containerd"
    printf 'version = 3\n[plugins."io.containerd.cri.v1.runtime"]\n  restrict_oom_score_adj = true\n' >"$STATE/containerd-restrict-oom.toml"
    volumes+="  - volume: $STATE/containerd-restrict-oom.toml:/var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml.d/10-restrict-oom.toml
    nodeFilters: [all]
"
  fi
  if [ -n "$volumes" ]; then
    printf 'volumes:\n%s' "$volumes" >>"$STATE/k3d.yaml"
  fi
  if [ -n "${DOCKERHUB_USER:-}" ] && [ -n "${DOCKERHUB_TOKEN:-}" ]; then
    cat >>"$STATE/k3d.yaml" <<EOF
registries:
  config: |
    configs:
      "registry-1.docker.io":
        auth:
          username: $DOCKERHUB_USER
          password: $DOCKERHUB_TOKEN
EOF
  fi
}

https_port_yaml() {
  # Port 443 comes straight from the control-plane node, like port 80.
  https_on || return 0
  if port_in_use 443; then
    c_warn "port 443 is already used on this machine, so HTTPS stays off (plain HTTP works)" >&2
    return 0
  fi
  printf '  - port: %s:443:443\n    nodeFilters: [server:0:direct]\n' "$LAB_BIND"
}

port_in_use() {
  if command -v ss >/dev/null; then ss -ltnH "sport = :$1" 2>/dev/null | grep . >/dev/null
  else (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
  fi
}

cluster_exists() { k3d cluster list -o json 2>/dev/null | grep "\"name\":\"$CLUSTER\"" >/dev/null; }

build_image() {
  # The image name is recorded only once the image is built and on every
  # node, so a failed build is simply retried by the next apply or rebuild.
  local img; img="$(image_ref)"
  if docker image inspect "$img" >/dev/null 2>&1; then
    c_ok "image $img already built"
  else
    c_info "Building application image $img"
    # shellcheck disable=SC2086
    docker build $DOCKER_BUILD_FLAGS -t "$img" "$ROOT/app" ||
      die "the application image did not build. If the output above says 429 Too Many Requests, Docker Hub's pull limit was reached: wait a few minutes, then run the same command again."
  fi
  if cluster_exists; then
    c_info "Loading image into the cluster nodes"
    local n
    for n in 1 2 3; do
      k3d image import "$img" -c "$CLUSTER" >/dev/null 2>&1 || true
      if image_on_all_nodes "$img"; then echo "$img" >"$STATE/image"; return 0; fi
      c_warn "image import incomplete (attempt $n), retrying"
      sleep 3
    done
    die "could not load $img into every node; run ./lab.sh rebuild again"
  fi
  echo "$img" >"$STATE/image"
}

image_on_all_nodes() {
  local node tag="${1##*:}"
  for node in $(k3d node list -o json 2>/dev/null | python3 -c 'import json,sys; [print(n["name"]) for n in json.load(sys.stdin) if n.get("role") in ("server","agent")]'); do
    # grep without -q reads all input; with pipefail, -q could fail the pipeline on SIGPIPE
    docker exec "$node" crictl images 2>/dev/null | grep "$tag" >/dev/null || return 1
  done
}

create_cluster() {
  if cluster_exists; then
    c_ok "cluster $CLUSTER exists"
    docker start "k3d-$CLUSTER-agent-0" "k3d-$CLUSTER-agent-1" >/dev/null 2>&1 || true
  else
    # A port 443 forwarder left from an older cluster would block the new one.
    docker rm -f relnusa-https >/dev/null 2>&1 || true
    write_k3d_config
    c_info "Creating 3-node Kubernetes cluster (1 control plane + 2 workers)"
    k3d cluster create --config "$STATE/k3d.yaml"
    echo "$LAB_BIND" >"$STATE/bind"
  fi
  check_bind
  kubectl config use-context "k3d-$CLUSTER" >/dev/null
  traefik_config | kubectl apply -f - >/dev/null
  ensure_https_port
  pin_system_pods
}

traefik_config() {
  # Settings for the Traefik ingress that ships with k3s, plus HTTPS when on.
  cat "$ROOT/k8s/cluster/traefik-config.yaml"
  https_on || return 0
  {
    cat <<EOF
# HTTPS: each lab host name gets a Let's Encrypt certificate, checked over
# port 80 (HTTP-01). The certificates are kept on a small volume, so a
# restart reuses them instead of asking again. Plain HTTP keeps working.
# The delay lets a Traefik rollout finish first: until the old pod is gone,
# it may answer the check instead of the new one.
persistence:
  enabled: true
  size: 128Mi
certificatesResolvers:
  le:
    acme:
      caServer: $LAB_ACME_CA
      storage: /data/acme.json
      httpChallenge:
        entryPoint: web
        delay: 30s
EOF
    if [ -n "$LAB_ACME_EMAIL" ]; then echo "      email: $LAB_ACME_EMAIL"; fi
    cat <<'EOF'
ports:
  websecure:
    http:
      tls:
        enabled: true
        certResolver: le
EOF
  } | sed 's/^/    /'
}

apply_traefik_config() {
  # k3s applies new Traefik settings with a helm job and then rolls the pod;
  # wait for both, so the next steps see the new settings.
  local before out t=0
  before="$(kubectl -n kube-system get job helm-install-traefik -o jsonpath='{.metadata.uid}' 2>/dev/null || true)"
  out="$(traefik_config | kubectl apply -f - 2>&1)" || die "could not apply the Traefik settings: $out"
  case "$out" in *unchanged*) return 0;; esac
  until [ "$(kubectl -n kube-system get job helm-install-traefik -o jsonpath='{.metadata.uid} {.status.succeeded}' 2>/dev/null)" != "$before 1" ] &&
        [ "$(kubectl -n kube-system get job helm-install-traefik -o jsonpath='{.status.succeeded}' 2>/dev/null)" = 1 ]; do
    sleep 3; t=$((t+3))
    if [ $t -ge 180 ]; then c_warn "Traefik settings not applied after 3 minutes (check: kubectl -n kube-system get pods)"; return 0; fi
  done
  kubectl -n kube-system rollout status deploy/traefik --timeout=180s >/dev/null 2>&1 || c_warn "Traefik is still restarting"
}

https_port_direct() { docker port "k3d-$CLUSTER-server-0" 443/tcp >/dev/null 2>&1; }

ensure_https_port() {
  # Clusters created before HTTPS support do not publish port 443. Instead of
  # rebuilding them, a small TCP forwarder container publishes it.
  if ! https_on || https_port_direct; then
    docker rm -f relnusa-https >/dev/null 2>&1 || true
    return 0
  fi
  [ "$(docker inspect -f '{{.State.Running}}' relnusa-https 2>/dev/null)" = true ] && return 0
  docker rm -f relnusa-https >/dev/null 2>&1 || true
  if port_in_use 443; then
    c_warn "port 443 is already used on this machine, so HTTPS is not published (plain HTTP works)"
    return 0
  fi
  local img
  img="$(docker inspect -f '{{.Config.Image}}' "k3d-$CLUSTER-serverlb" 2>/dev/null || echo "ghcr.io/k3d-io/k3d-proxy:${K3D_VERSION#v}")"
  cat >"$STATE/https-forwarder.conf" <<EOF
# Port 443 forwarder for the lab (written by lab.sh).
worker_processes 1;
error_log stderr notice;
events { worker_connections 1024; }
stream {
  # Docker's DNS, asked again for each connection, so a node that comes back
  # with a new IP after a reboot is still found.
  resolver 127.0.0.11 valid=10s ipv6=off;
  server {
    listen 443;
    set \$lab_node k3d-$CLUSTER-server-0:443;
    proxy_pass \$lab_node;
    proxy_connect_timeout 2s;
    proxy_timeout 600s;
  }
}
EOF
  # The k3d load balancer image is already on this machine and is plain nginx.
  if docker run -d --name relnusa-https --restart unless-stopped --network "k3d-$CLUSTER" \
      -p "$LAB_BIND:443:443" -v "$STATE/https-forwarder.conf:/etc/nginx/nginx.conf:ro" \
      --entrypoint nginx "$img" -g 'daemon off;' >/dev/null; then
    c_ok "port 443 forwarded to the cluster"
  else
    c_warn "could not publish port 443; plain HTTP works"
  fi
}

wait_https() {
  # Let's Encrypt usually answers within a minute of the host names appearing.
  https_on || return 0
  c_info "Waiting for the Let's Encrypt certificates (up to 4 minutes)"
  local t=0
  until https_valid app && https_valid grafana; do
    sleep 5; t=$((t+5))
    if [ $t -ge 240 ]; then
      c_warn "no trusted HTTPS certificate yet; plain HTTP works meanwhile. Details: ./lab.sh preflight"
      return 0
    fi
  done
  c_ok "HTTPS certificates issued"
}

check_bind() {
  # The listening address is fixed when the cluster is created.
  local made; made="$(cat "$STATE/bind" 2>/dev/null || echo 127.0.0.1)"
  if [ "$made" != "$LAB_BIND" ]; then
    c_warn "the cluster listens on $made, but LAB_ACCESS=$LAB_ACCESS needs $LAB_BIND."
    c_warn "recreate it to switch (about 10 minutes, images are kept): ./lab.sh down && ./lab.sh up"
  fi
}

pin_system_pods() {
  # Keep cluster DNS and the other k3s add-ons on the control-plane node, which
  # the demos never stop. If CoreDNS sat on a node that node-down stops, name
  # lookups would fail for minutes and the "modern survives" demo would not.
  local d t=0
  until kubectl -n kube-system get deploy coredns >/dev/null 2>&1; do sleep 3; t=$((t+3)); [ $t -lt 180 ] || break; done
  for d in coredns metrics-server local-path-provisioner; do
    kubectl -n kube-system patch deployment "$d" --type=strategic \
      -p '{"spec":{"template":{"spec":{"nodeSelector":{"node-role.kubernetes.io/control-plane":"true"}}}}}' >/dev/null 2>&1 ||
      c_warn "could not pin $d to the control-plane node"
  done
  kubectl -n kube-system rollout status deploy/coredns --timeout=120s >/dev/null 2>&1 || c_warn "CoreDNS is not ready yet"
}

helm_repos() {
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo add chaos-mesh https://charts.chaos-mesh.org >/dev/null 2>&1 || true
  helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
  helm repo add cnpg https://cloudnative-pg.github.io/charts >/dev/null 2>&1 || true
  helm repo update >/dev/null
}

alertmanager_values() {
  local f="$STATE/alertmanager-values.yaml"
  if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
    cat >"$f" <<EOF
alertmanager:
  config:
    global:
      resolve_timeout: 5m
    route:
      receiver: "null"
      group_by: [alertname, sloth_service, sloth_slo]
      group_wait: 10s
      group_interval: 30s
      repeat_interval: 2h
      routes:
        - receiver: telegram
          matchers: ['sloth_slo=~".+"']
    receivers:
      - name: "null"
      - name: telegram
        telegram_configs:
          - bot_token: "$TELEGRAM_BOT_TOKEN"
            chat_id: $TELEGRAM_CHAT_ID
            parse_mode: HTML
            send_resolved: true
            message: '{{ template "relnusa.telegram" . }}'
    templates:
      - /etc/alertmanager/config/*.tmpl
EOF
  else
    cat >"$f" <<'EOF'
alertmanager:
  config:
    global:
      resolve_timeout: 5m
    route:
      receiver: "null"
      group_by: [alertname, sloth_service, sloth_slo]
      group_wait: 10s
      group_interval: 30s
      repeat_interval: 2h
    receivers:
      - name: "null"
    templates:
      - /etc/alertmanager/config/*.tmpl
EOF
  fi
  chmod 600 "$f"
  echo "$f"
}

install_platform() {
  helm_repos
  render "$ROOT/k8s/platform/kps-values.yaml" >"$STATE/kps-values.yaml"
  chmod 600 "$STATE/kps-values.yaml"
  c_info "Monitoring: Prometheus, Alertmanager, Grafana"
  helm upgrade --install kps prometheus-community/kube-prometheus-stack -n observability --create-namespace \
    --version "$KPS_CHART_VERSION" -f "$STATE/kps-values.yaml" -f "$(alertmanager_values)" --wait --timeout 20m >/dev/null
  c_ok "monitoring"
  c_info "Database operator, release controller and chaos tool (in parallel)"
  local pids=() names=()
  helm upgrade --install cnpg cnpg/cloudnative-pg -n cnpg-system --create-namespace --version "$CNPG_CHART_VERSION" \
    -f "$ROOT/k8s/platform/cnpg-values.yaml" --wait --timeout 15m >"$STATE/helm-cnpg.log" 2>&1 & pids+=($!); names+=(cnpg)
  helm upgrade --install argo-rollouts argo/argo-rollouts -n argo-rollouts --create-namespace --version "$ROLLOUTS_CHART_VERSION" \
    -f "$ROOT/k8s/platform/argo-rollouts-values.yaml" --wait --timeout 15m >"$STATE/helm-rollouts.log" 2>&1 & pids+=($!); names+=(argo-rollouts)
  helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh -n chaos-mesh --create-namespace --version "$CHAOS_CHART_VERSION" \
    -f "$ROOT/k8s/platform/chaos-mesh-values.yaml" --wait --timeout 15m >"$STATE/helm-chaos.log" 2>&1 & pids+=($!); names+=(chaos-mesh)
  local i
  for i in "${!pids[@]}"; do
    if wait "${pids[$i]}"; then c_ok "${names[$i]}"; else c_warn "${names[$i]} failed, see $STATE/helm-${names[$i]%%-*}.log"; fi
  done
  c_info "Tracing: OpenTelemetry Collector and Jaeger"
  kubectl apply -f "$ROOT/k8s/platform/tracing.yaml" >/dev/null
  render "$ROOT/k8s/platform/tool-ingress.yaml" | kubectl apply -f - >/dev/null
  c_ok "tracing"
}

deploy_apps() {
  c_info "Deploying the bank simulator, legacy system and modern system"
  kubectl apply -f "$ROOT/k8s/apps/00-namespaces.yaml" >/dev/null
  render "$ROOT/k8s/apps/bank.yaml" | kubectl apply -f - >/dev/null
  render "$ROOT/k8s/apps/bank-ingress.yaml" | kubectl apply -f - >/dev/null
  render "$ROOT/k8s/apps/legacy.yaml" | kubectl apply -f - >/dev/null
  render "$ROOT/k8s/apps/modern-data.yaml" | kubectl apply -f - >/dev/null
  kubectl apply -f "$ROOT/k8s/apps/monitors.yaml" >/dev/null
  c_info "Waiting for the PostgreSQL cluster (primary + replicas)"
  local t=0
  until kubectl -n modern get secret relnusa-db-app >/dev/null 2>&1; do sleep 5; t=$((t+5)); [ $t -lt 600 ] || die "database secret not created"; done
  kubectl -n modern wait cluster/relnusa-db --for=condition=Ready --timeout=900s >/dev/null
  c_ok "database cluster ready"
  render "$ROOT/k8s/apps/modern.yaml" | kubectl apply -f - >/dev/null
  if ! kubectl -n modern get rollout booking >/dev/null 2>&1; then
    render "$ROOT/k8s/apps/booking-rollout.tpl.yaml" v1 0 | kubectl apply -f - >/dev/null
  fi
  apply_tool_auth
  apply_observability_content
  echo "$LAB_DOMAIN" >"$STATE/applied-domain"
  c_info "Waiting for all services to be ready"
  kubectl -n bank rollout status deploy/banksim --timeout=300s >/dev/null
  kubectl -n legacy rollout status deploy/legacy-db --timeout=300s >/dev/null
  kubectl -n legacy rollout status deploy/monolith --timeout=300s >/dev/null
  kubectl -n modern rollout status deploy/redis --timeout=300s >/dev/null
  kubectl -n modern rollout status deploy/search --timeout=300s >/dev/null
  kubectl -n modern rollout status deploy/gateway --timeout=300s >/dev/null
  kubectl -n modern rollout status deploy/payment-worker --timeout=300s >/dev/null
  kubectl argo rollouts status booking -n modern --timeout 300s >/dev/null
  c_ok "all services ready"
}

apply_observability_content() {
  local f
  # The dashboard files got English names; remove the old ones so Grafana
  # does not keep a second copy of each dashboard.
  if kubectl -n observability get configmap relnusa-dashboard-00 -o jsonpath='{.data}' 2>/dev/null | grep -q ringkasan; then
    kubectl -n observability delete configmap relnusa-dashboard-00 relnusa-dashboard-01 --ignore-not-found >/dev/null
  fi
  for f in "$ROOT"/k8s/slo/rules/*.yaml "$ROOT"/k8s/dashboards/*.yaml; do
    [ -f "$f" ] && render "$f" | kubectl apply -f - >/dev/null
  done
  return 0
}

apply_tool_auth() {
  # One login (admin and the Grafana password) in front of the operator
  # tools: Prometheus, Alertmanager, Jaeger, Chaos Mesh, Argo Rollouts and the
  # bank's admin API. Grafana has its own login; the two sites stay open.
  local users ns
  users="admin:$(openssl passwd -apr1 "$(grafana_password)")"
  for ns in observability chaos-mesh argo-rollouts bank; do
    kubectl -n "$ns" create secret generic lab-auth --from-literal=users="$users" --dry-run=client -o yaml |
      kubectl apply -f - >/dev/null
  done
  kubectl apply -f "$ROOT/k8s/platform/tool-auth.yaml" >/dev/null
}

apply_hostnames() {
  # Re-apply everything that carries a host name, after the domain changed.
  helm_repos
  render "$ROOT/k8s/platform/kps-values.yaml" >"$STATE/kps-values.yaml"
  chmod 600 "$STATE/kps-values.yaml"
  helm upgrade kps prometheus-community/kube-prometheus-stack -n observability --version "$KPS_CHART_VERSION" \
    -f "$STATE/kps-values.yaml" -f "$(alertmanager_values)" --wait --timeout 10m >/dev/null
  render "$ROOT/k8s/platform/tool-ingress.yaml" | kubectl apply -f - >/dev/null
  render "$ROOT/k8s/apps/bank-ingress.yaml" | kubectl apply -f - >/dev/null
  render "$ROOT/k8s/apps/legacy.yaml" | kubectl apply -f - >/dev/null
  render "$ROOT/k8s/apps/modern.yaml" | kubectl apply -f - >/dev/null
  apply_tool_auth
  apply_observability_content
  echo "$LAB_DOMAIN" >"$STATE/applied-domain"
  if docker ps -a --filter name=relnusa-traffic --format '{{.Names}}' | grep relnusa-traffic >/dev/null; then cmd_traffic start; fi
}

cmd_update_ip() {
  # Point every host name at the current public IP (or at LAB_DOMAIN).
  local applied new
  applied="$(cat "$STATE/applied-domain" 2>/dev/null || echo localhost)"
  new="$(desired_domain)"
  check_bind
  if [ "$new" = "$applied" ] && kubectl -n bank get middlewares.traefik.io lab-auth >/dev/null 2>&1; then
    c_ok "host names are up to date ($new)"; return 0
  fi
  c_info "Applying host names *.$new and the tools login (about 2 minutes)"
  LAB_DOMAIN="$new"
  apply_hostnames
  wait_https
  c_ok "done. Addresses: ./lab.sh info"
}

cmd_update() {
  # Fetch the latest lab code, then apply it to the running cluster.
  local owner; owner="$(stat -c %U "$ROOT")"
  c_info "Fetching the latest lab code"
  if [ "$owner" = root ]; then git -C "$ROOT" pull --ff-only
  else sudo -u "$owner" -H git -C "$ROOT" pull --ff-only
  fi || die "could not update the code (local changes? see: git -C $ROOT status)"
  exec bash "$ROOT/lab.sh" apply
}

cmd_apply() {
  # Re-apply the lab's settings to the running cluster, for example after
  # ./lab.sh update or a change in lab.env. Data, images and releases stay.
  cluster_exists || die "no cluster yet; run ./lab.sh up"
  check_bind
  [ "$(image_ref)" = "$(cat "$STATE/image" 2>/dev/null)" ] || cmd_rebuild
  LAB_DOMAIN="$(desired_domain)"
  c_info "Host names *.$LAB_DOMAIN, tools login and dashboards (about 2 minutes)"
  apply_hostnames
  # After the host names, so certificates are only requested for current ones.
  c_info "Ingress settings$(https_on && echo " and HTTPS")"
  apply_traefik_config
  ensure_https_port
  install_boot_service
  wait_https
  cmd_info
}

roll_app_pods() {
  local img; img="$(cat "$STATE/image")"
  for ns_d in bank/banksim legacy/monolith modern/gateway modern/search modern/payment-worker; do
    kubectl -n "${ns_d%%/*}" set image "deploy/${ns_d##*/}" "*=$img" >/dev/null
  done
  render "$ROOT/k8s/apps/booking-rollout.tpl.yaml" "$(current_version)" "$(current_fault)" | kubectl apply -f - >/dev/null
}

current_version() { kubectl -n modern get rollout booking -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="APP_VERSION")].value}' 2>/dev/null || echo v1; }
current_fault() { kubectl -n modern get rollout booking -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="FAULT_ERROR_RATE")].value}' 2>/dev/null || echo 0; }

cmd_up() {
  need docker; need k3d; need kubectl; need helm
  local start; start=$(date +%s)
  build_image
  create_cluster
  build_image
  install_platform
  deploy_apps
  cmd_traffic start
  install_boot_service
  wait_https
  c_ok "lab is up in $(( ($(date +%s) - start) / 60 )) minutes"
  cmd_info
}

install_boot_service() {
  # After a VM stop/start, Docker restarts the node containers in random order,
  # which can leave a node "NotReady". This unit restarts the cluster in order.
  [ -d /run/systemd/system ] || return 0
  cat >/etc/systemd/system/relnusa-lab.service <<UNIT
[Unit]
Description=RelNusa lab: restart the k3d cluster in order after boot
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
TimeoutStartSec=900
ExecStart=$ROOT/lab.sh boot

[Install]
WantedBy=multi-user.target
UNIT
  if systemctl daemon-reload && systemctl enable relnusa-lab.service >/dev/null 2>&1; then
    c_ok "boot service installed: the cluster restarts cleanly after a VM reboot"
  else
    c_warn "could not enable the boot service; after a reboot run ./lab.sh restart"
  fi
}

heal_nodes() {
  # k3s on a node container can exit during start-up (for example while the
  # control plane is still coming up) and does not try again by itself.
  # Restart any node that stays NotReady.
  local attempt t bad node
  for t in $(seq 1 40); do kubectl get nodes >/dev/null 2>&1 && break; sleep 3; done
  for attempt in 1 2 3; do
    for t in $(seq 1 30); do
      bad="$(kubectl get nodes --no-headers 2>/dev/null | awk '$2!="Ready"{print $1}')"
      [ -z "$bad" ] && [ "$(kubectl get nodes --no-headers 2>/dev/null | wc -l)" -ge 3 ] && return 0
      sleep 3
    done
    for node in $bad; do
      c_warn "node $node is not ready; restarting it (attempt $attempt)"
      docker restart -t 10 "$node" >/dev/null 2>&1 || true
    done
  done
  return 1
}

after_start() {
  # Shared tail of restart and boot.
  pin_system_pods
  docker start relnusa-traffic >/dev/null 2>&1 || true
  ensure_https_port
  if [ "$LAB_ACCESS" = public ] && [ -z "$LAB_DOMAIN_FIXED" ]; then
    # A stopped and started VM usually gets a new public IP.
    kubectl -n observability rollout status deploy/kps-grafana --timeout=300s >/dev/null 2>&1 || true
    cmd_update_ip || c_warn "could not update the host names; run ./lab.sh update-ip"
  fi
}

cmd_restart() {
  # Stop and start the whole cluster, then heal any node that did not come back.
  cluster_exists || die "no cluster yet; run ./lab.sh up"
  c_info "Restarting the cluster (about 2 minutes)"
  k3d cluster stop "$CLUSTER" >/dev/null 2>&1 || true
  k3d cluster start "$CLUSTER" --timeout 180s >/dev/null 2>&1 || c_warn "k3d start did not finish cleanly; checking the nodes"
  docker start "k3d-$CLUSTER-serverlb" >/dev/null 2>&1 || true
  kubectl config use-context "k3d-$CLUSTER" >/dev/null
  heal_nodes || c_warn "not every node is ready; check with: kubectl get nodes"
  after_start
  c_ok "cluster restarted; pods need another minute or two (check with ./lab.sh preflight)"
}

cmd_boot() {
  # Run by the boot service after a VM start. Docker has already started the
  # node containers; only restart what did not come back.
  cluster_exists || return 0
  docker start "k3d-$CLUSTER-serverlb" "k3d-$CLUSTER-server-0" "k3d-$CLUSTER-agent-0" "k3d-$CLUSTER-agent-1" >/dev/null 2>&1 || true
  kubectl config use-context "k3d-$CLUSTER" >/dev/null 2>&1 || true
  if heal_nodes; then after_start; c_ok "cluster is up after boot"; else cmd_restart; fi
}

cmd_rebuild() {
  build_image
  roll_app_pods
  c_ok "application pods are rolling to $(cat "$STATE/image")"
}

cmd_down() {
  cmd_traffic stop || true
  docker rm -f relnusa-https >/dev/null 2>&1 || true
  k3d cluster delete "$CLUSTER"
}

# ---------------------------------------------------------------- traffic
k6_run() {
  # shellcheck disable=SC2068
  docker run --rm --network host -v "$ROOT/load:/scripts:ro" \
    -e K6_PROMETHEUS_RW_SERVER_URL="http://127.0.0.1:$PROM_PORT/api/v1/write" \
    -e K6_PROMETHEUS_RW_TREND_STATS="p(95),p(99),avg" \
    -e K6_PROMETHEUS_RW_PUSH_INTERVAL=5s \
    -e HTTP_PORT="$HTTP_PORT" -e LAB_DOMAIN="$LAB_DOMAIN" \
    $@
}

cmd_traffic() {
  case "${1:-status}" in
    start)
      docker rm -f relnusa-traffic >/dev/null 2>&1 || true
      docker run -d --name relnusa-traffic --restart unless-stopped --network host \
        -v "$ROOT/load:/scripts:ro" \
        -e K6_PROMETHEUS_RW_SERVER_URL="http://127.0.0.1:$PROM_PORT/api/v1/write" \
        -e HTTP_PORT="$HTTP_PORT" -e LAB_DOMAIN="$LAB_DOMAIN" \
        -e K6_PROMETHEUS_RW_TREND_STATS="p(95),p(99),avg" \
        -e K6_PROMETHEUS_RW_PUSH_INTERVAL=5s \
        -e RATE="$TRAFFIC_RATE" \
        "$K6_IMAGE" run --quiet --no-summary --out experimental-prometheus-rw /scripts/steady.js >/dev/null
      c_ok "background traffic started ($TRAFFIC_RATE journeys per second per site)";;
    stop) docker rm -f relnusa-traffic >/dev/null 2>&1 && c_ok "background traffic stopped" || true;;
    status) docker ps --filter name=relnusa-traffic --format 'traffic: {{.Status}}' ;;
    *) die "usage: traffic start|stop|status";;
  esac
}

cmd_spike() {
  local target="${1:-modern}" peak="${2:-150}" hold="${3:-90s}"
  [ "$target" = legacy ] || [ "$target" = modern ] || die "usage: spike legacy|modern [peak-per-second] [hold]"
  c_info "Ticket rush against the $target site: up to $peak new buyers per second for $hold"
  k6_run -e TARGET="$target" -e PEAK_RATE="$peak" -e HOLD="$hold" "$K6_IMAGE" run --out experimental-prometheus-rw /scripts/ticket-rush.js
}

# ---------------------------------------------------------------- faults
bank_api() { lab_curl bank "/admin/config${2:-}" -X "$1"; echo; }

cmd_bank() {
  case "${1:-status}" in
    normal|slow|errors|down) bank_api PUT "?mode=$1";;
    status) bank_api GET;;
    *) die "usage: bank normal|slow|errors|down|status";;
  esac
}

chaos_stop() {
  # Remove experiments without hanging on stage: if Chaos Mesh cannot clean up
  # within 30 s (for example a network fault that never got injected), the
  # finalizers are cleared so the objects go away anyway.
  # All experiments, also ones started under the names of earlier lab versions.
  kubectl delete podchaos,networkchaos --all -A --wait=false >/dev/null 2>&1 || true
  local t=0 left
  while :; do
    left="$(kubectl get podchaos,networkchaos -A -o jsonpath='{range .items[*]}{.kind}/{.metadata.name} -n {.metadata.namespace}{"\n"}{end}' 2>/dev/null)"
    [ -z "$left" ] && break
    if [ $t -ge 30 ]; then
      echo "$left" | while read -r obj _ ns; do
        [ -n "$obj" ] && kubectl -n "$ns" patch "$obj" --type=merge -p '{"metadata":{"finalizers":[]}}' >/dev/null 2>&1 || true
      done
      c_warn "some experiments did not clean up by themselves; their finalizers were cleared"
      break
    fi
    sleep 2; t=$((t+2))
  done
}

cmd_chaos() {
  local name="${1:-list}"
  case "$name" in   # names used by earlier versions of the lab
    bank-lambat) name=bank-slow;;
    matikan-*) name="kill-${name#matikan-}";;
  esac
  case "$name" in
    list) ls "$ROOT/chaos" | sed 's/\.yaml$//'; kubectl get podchaos,networkchaos -A 2>/dev/null || true;;
    stop) chaos_stop; c_ok "all chaos experiments removed";;
    *)
      [ -f "$ROOT/chaos/$name.yaml" ] || die "unknown experiment '$name' (see: ./lab.sh chaos list)"
      if grep -q '^kind: NetworkChaos' "$ROOT/chaos/$name.yaml" && [ ! -d /sys/module/sch_netem ]; then
        # The k3d nodes share this machine's kernel, so the delay needs netem here.
        modprobe sch_netem 2>/dev/null || sudo -n modprobe sch_netem 2>/dev/null || true
        [ -d /sys/module/sch_netem ] || die "this kernel has no netem module, so Chaos Mesh cannot add network delay.
    Use the same fault inside the bank simulator instead:  ./lab.sh bank slow   (undo: ./lab.sh bank normal)"
      fi
      kubectl delete -f "$ROOT/chaos/$name.yaml" --ignore-not-found --wait=false >/dev/null 2>&1 || true
      kubectl apply -f "$ROOT/chaos/$name.yaml" >/dev/null
      c_ok "experiment $name started (stop with: ./lab.sh chaos stop)";;
  esac
}

primary_node() { kubectl -n modern get pod -l cnpg.io/cluster=relnusa-db,cnpg.io/instanceRole=primary -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null; }

cmd_db_primary_away() {
  # Move the database primary off a node before that node is stopped.
  local node="$1" target
  [ "$(primary_node)" = "$node" ] || return 0
  target="$(kubectl -n modern get pod -l cnpg.io/cluster=relnusa-db,cnpg.io/instanceRole=replica -o jsonpath='{range .items[*]}{.metadata.name} {.spec.nodeName}{"\n"}{end}' | awk -v n="$node" '$2!=n && !f {print $1; f=1}')"
  [ -n "$target" ] || { c_warn "no replica on another node"; return 0; }
  c_info "Database primary is on $node; switching it to $target first"
  kubectl cnpg promote relnusa-db "$target" -n modern >/dev/null
  local t=0; until [ "$(primary_node)" != "$node" ] && [ -n "$(primary_node)" ]; do sleep 3; t=$((t+3)); [ $t -lt 180 ] || break; done
  sleep 10
}

cmd_node() {
  local action="$1" n="${2:-0}" name="k3d-$CLUSTER-agent-${2:-0}" zone
  case "$action" in
    down)
      pin_system_pods
      if [ "${KEEP_DB_PRIMARY:-yes}" = yes ]; then cmd_db_primary_away "$name"; fi
      zone="$(kubectl get node "$name" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}' 2>/dev/null || true)"
      c_info "Stopping node $name${zone:+ ($zone)}"
      docker stop "$name" >/dev/null; c_ok "node stopped. Bring it back with: ./lab.sh node-up $n";;
    up) docker start "$name" >/dev/null; c_ok "node $name started";;
  esac
}

cmd_release() {
  local v f
  case "${1:-}" in
    good) v=v2; f=0;;
    bad) v=v3-bug; f=0.3;;
    undo|stable) v=v1; f=0;;
    *) die "usage: release good|bad|undo";;
  esac
  render "$ROOT/k8s/apps/booking-rollout.tpl.yaml" "$v" "$f" | kubectl apply -f - >/dev/null
  c_ok "booking $v submitted. Watch it: kubectl argo rollouts get rollout booking -n modern --watch"
}

cmd_legacy_deploy() {
  c_info "Deploying a new monolith version the classic way (stop, then start)"
  kubectl -n legacy rollout restart deploy/monolith >/dev/null
  kubectl -n legacy rollout status deploy/monolith --timeout=300s
}

cmd_reset() {
  c_info "Resetting bookings and seats (legacy and modern)"
  kubectl -n legacy exec deploy/monolith -- relnusa reset
  kubectl -n modern exec deploy/payment-worker -- relnusa reset
  cmd_bank normal >/dev/null || true
  c_ok "data reset"
}

cmd_telegram_test() {
  local now; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  lab_curl alertmanager /api/v2/alerts -X POST -H 'Content-Type: application/json' -d "[{\"labels\":{\"alertname\":\"TestNotification\",\"sloth_service\":\"relnusa-modern\",\"sloth_slo\":\"test\",\"severity\":\"info\"},\"annotations\":{\"title\":\"Alert path test\",\"summary\":\"If you can read this, alerts from the lab reach Telegram.\"},\"startsAt\":\"$now\"}]"
  c_ok "test alert sent to Alertmanager (arrives in Telegram within about 15 seconds if configured)"
}

cmd_info() {
  local pw; pw="$(grafana_password)"
  detect_scheme
  echo
  if [ "$LAB_ACCESS" = public ]; then
    cat <<EOF
RelNusa lab ($LAB_PROFILE profile), open from anywhere:

  Legacy site       $(site_url legacy)
  Modern site       $(site_url app)
  Grafana           $(site_url grafana)   (view without login; edit as admin / $pw)

Operator tools (login: admin / $pw):

  Jaeger traces     $(site_url jaeger)
  Chaos Mesh        $(site_url chaos)
  Argo Rollouts     $(site_url rollouts)
  Prometheus        $(site_url prometheus)
  Alertmanager      $(site_url alertmanager)

EOF
    if [ "$URL_SCHEME" = https ]; then
      echo "Certificates are from Let's Encrypt; the same addresses also work with http://."
      echo "The firewall must allow TCP 80 and 443 from anywhere."
    elif https_on; then
      echo "HTTPS has no trusted certificate yet, so use http:// for now (details: ./lab.sh preflight)."
      echo "The firewall must allow TCP 80 and 443 from anywhere."
    else
      echo "The firewall must allow TCP $HTTP_PORT from anywhere."
    fi
    echo "If the IP changes after a restart, the names follow by themselves (or run ./lab.sh update-ip)."
  else
    local ip; ip="$(public_ip 2>/dev/null || hostname -I | awk '{print $1}')"
    cat <<EOF
RelNusa lab ($LAB_PROFILE profile). From your laptop, open an SSH tunnel:

  ssh -N -L 8080:127.0.0.1:$HTTP_PORT <user>@$ip

then browse (Chrome or Edge resolve *.localhost automatically):

  Legacy site       $(site_url legacy)
  Modern site       $(site_url app)
  Grafana           $(site_url grafana)   (view without login; edit as admin / $pw)
  Jaeger traces     $(site_url jaeger)   (tools login: admin / $pw)
  Chaos Mesh        $(site_url chaos)
  Argo Rollouts     $(site_url rollouts)
  Prometheus        $(site_url prometheus)
  Alertmanager      $(site_url alertmanager)
EOF
  fi
  cat <<EOF

Telegram alerts: $([ -n "${TELEGRAM_BOT_TOKEN:-}" ] && echo "on (chat ${TELEGRAM_CHAT_ID:-?})" || echo "off (set TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID in lab.env, then ./lab.sh alerts)")
Demo commands: ./lab.sh help
EOF
}

cmd_alerts() {
  helm upgrade kps prometheus-community/kube-prometheus-stack -n observability --version "$KPS_CHART_VERSION" \
    -f "$STATE/kps-values.yaml" -f "$(alertmanager_values)" --wait --timeout 10m >/dev/null
  c_ok "alert routing updated"
}

cmd_status() {
  kubectl get nodes -L topology.kubernetes.io/zone
  echo
  kubectl get pods -n legacy -o wide
  echo
  kubectl get pods -n modern -o wide
  echo
  kubectl -n modern get cluster relnusa-db 2>/dev/null || true
  echo "database primary on: $(primary_node)"
  cmd_traffic status
  cmd_bank status 2>/dev/null || true
}

prom_value() {
  # First value of an instant query, or empty.
  curl -fsS -m 5 "http://127.0.0.1:$PROM_PORT/api/v1/query" --data-urlencode "query=$1" 2>/dev/null |
    python3 -c 'import json,sys
r=json.load(sys.stdin)["data"]["result"]
print(r[0]["value"][1] if r else "")' 2>/dev/null || true
}

cmd_preflight() {
  # One command to run before going on stage. Hard problems make it exit 1;
  # warnings are things worth knowing but not blocking.
  local bad=0 n v age
  fail() { printf '\033[1;31m XX\033[0m %s\n' "$*"; bad=$((bad+1)); }

  n="$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l)"
  [ "$n" -ge 3 ] && c_ok "3 nodes ready" || fail "only $n of 3 nodes ready (./lab.sh node-up 0 ; ./lab.sh node-up 1)"

  v="$(kubectl get pods -A --no-headers 2>/dev/null | awk '$4!="Completed" { split($3,a,"/"); if (a[1]!=a[2] || $4!="Running") print $1"/"$2" "$4 }')"
  [ -z "$v" ] && c_ok "all pods running and ready" || fail "pods not ready: $(echo "$v" | tr '\n' ' ')"

  for h in legacy app grafana; do
    v="$(curl -s -m 5 -o /dev/null -w '%{http_code}' -H "Host: $h.$LAB_DOMAIN" "http://127.0.0.1:$HTTP_PORT/" 2>/dev/null || true)"
    [ "$v" = 200 ] || [ "$v" = 302 ] && c_ok "$(site_url "$h") answers ($v)" || fail "$(site_url "$h") answers $v"
  done
  v="$(curl -s -m 5 -o /dev/null -w '%{http_code}' -H "Host: chaos.$LAB_DOMAIN" "http://127.0.0.1:$HTTP_PORT/" 2>/dev/null || true)"
  [ "$v" = 401 ] && c_ok "operator tools ask for the login" || fail "$(site_url chaos) answered $v without a login (expected 401; run ./lab.sh update-ip)"
  if [ "$LAB_ACCESS" = public ]; then
    v="$(curl -s -m 8 -o /dev/null -w '%{http_code}' "$(site_url app)/" 2>/dev/null || true)"
    if [ "$v" = 200 ]; then c_ok "reachable at its public address: $(site_url app)"
    else c_warn "$(site_url app) did not answer from this machine (got '${v:-nothing}'). Check that the firewall allows TCP $HTTP_PORT from anywhere, then try it from your phone"; fi
  fi
  if https_on; then
    local miss=""
    for h in app legacy grafana chaos; do https_valid "$h" || miss+="$h "; done
    if [ -z "$miss" ]; then c_ok "HTTPS certificates are trusted (Let's Encrypt)"
    else
      c_warn "no trusted HTTPS certificate yet for: ${miss}(plain HTTP works). Latest Traefik message about it:"
      kubectl -n kube-system logs deploy/traefik --since=60m 2>/dev/null | grep -i -E 'acme|certificate' | tail -n 1 | cut -c1-400 || true
    fi
    v="$(curl -sk -m 8 -o /dev/null -w '%{http_code}' "https://app.$LAB_DOMAIN/" 2>/dev/null || true)"
    if [ "$v" = 200 ]; then c_ok "reachable over HTTPS at https://app.$LAB_DOMAIN"
    else c_warn "https://app.$LAB_DOMAIN did not answer from this machine (got '${v:-nothing}'). Check that the firewall allows TCP 443 from anywhere"; fi
  fi

  v="$(kubectl -n modern get rollout booking -o jsonpath='{.status.phase} {.spec.template.spec.containers[0].env[?(@.name=="APP_VERSION")].value}' 2>/dev/null)"
  [ "$v" = "Healthy v1" ] && c_ok "booking release is v1 and healthy" || fail "booking release is '$v' (./lab.sh release undo)"

  v="$(kubectl -n modern get cluster relnusa-db -o jsonpath='{.status.phase}' 2>/dev/null)"
  [ "$v" = "Cluster in healthy state" ] && c_ok "database healthy, primary on $(primary_node)" || fail "database: $v"

  v="$(kubectl get podchaos,networkchaos -A --no-headers 2>/dev/null | wc -l)"
  [ "$v" = 0 ] && c_ok "no chaos experiments running" || fail "$v chaos experiments still running (./lab.sh chaos stop)"

  v="$(bank_api GET 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["mode"])' 2>/dev/null)"
  [ "$v" = normal ] && c_ok "bank is normal" || fail "bank mode is '${v:-unknown}' (./lab.sh bank normal)"

  if docker ps --filter name=relnusa-traffic --format '{{.Names}}' | grep relnusa-traffic >/dev/null; then
    age=$(( $(date +%s) - $(date -d "$(docker inspect -f '{{.State.StartedAt}}' relnusa-traffic)" +%s) ))
    if [ $age -ge 3600 ]; then c_ok "background traffic running for $((age/60)) minutes"
    else c_warn "background traffic running for only $((age/60)) minutes; start it at least an hour before the SLO demo so alert timing matches the slides"; fi
  else
    fail "background traffic is not running (./lab.sh traffic start)"
  fi

  v="$(prom_value 'count(up{namespace=~"legacy|modern|bank"} == 0) or vector(0)')"
  [ "$v" = 0 ] && c_ok "Prometheus scrapes every lab service" || fail "Prometheus cannot scrape $v lab targets"
  v="$(prom_value 'count(slo:current_burn_rate:ratio{sloth_service=~"relnusa-.*"})')"
  [ "$v" = 5 ] && c_ok "all 5 SLOs have data" || fail "only ${v:-0} of 5 SLOs have data"
  v="$(prom_value 'count(ALERTS{alertstate="firing",severity="page",sloth_service=~"relnusa-.*"})')"
  if [ -z "$v" ]; then c_ok "no page alerts firing"
  else c_warn "$v page alerts still firing from earlier tests (they clear by themselves within about 30 minutes): $(curl -fsS -m 5 "http://127.0.0.1:$PROM_PORT/api/v1/query" --data-urlencode 'query=ALERTS{alertstate="firing",severity="page",sloth_service=~"relnusa-.*"}' | python3 -c 'import json,sys; print(" ".join(sorted({r["metric"]["alertname"] for r in json.load(sys.stdin)["data"]["result"]})))')"; fi

  if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then c_ok "Telegram configured (check delivery with ./lab.sh telegram-test)"
  else c_warn "Telegram not configured; alerts are visible only in Alertmanager and Grafana"; fi

  if [ -d /sys/module/sch_netem ] || modprobe -n sch_netem 2>/dev/null; then c_ok "kernel supports network delay (chaos bank-slow)"
  else c_warn "no netem module: use ./lab.sh bank slow instead of ./lab.sh chaos bank-slow"; fi

  v="$(prom_value 'sum(payment_queue_pending{namespace="modern"})')"
  [ "${v%.*}" -le 20 ] 2>/dev/null && c_ok "payment queue is empty enough (${v%.*} pending)" || c_warn "payment queue has ${v:-?} pending jobs"

  echo
  if [ $bad -eq 0 ]; then c_ok "ready. If you already ran a rush today, run ./lab.sh reset first."; else die "$bad problem(s) above"; fi
}

cmd_help() {
  cat <<'EOF'
Setup
  sudo ./lab.sh install-deps     install Docker, k3d, kubectl, helm, plugins
  ./lab.sh up                    build and start everything (15-25 minutes the first time)
  ./lab.sh info                  addresses and the login
  ./lab.sh status                nodes, pods, database primary, traffic, bank mode
  ./lab.sh preflight             check everything before going on stage
  ./lab.sh restart               restart the cluster in order (nodes not ready after a reboot)
  ./lab.sh update-ip             point the host names at a new public IP (done by restart too)
  ./lab.sh update                fetch the latest lab code and apply it (keeps data)
  ./lab.sh apply                 re-apply settings after editing lab.env
  ./lab.sh down                  delete the cluster
  ./lab.sh rebuild               rebuild the app image and roll the pods
  ./lab.sh alerts                re-apply alert routing after editing lab.env

Session 1: modernization
  ./lab.sh spike legacy [150] [90s]   ticket rush against the legacy site
  ./lab.sh spike modern [150] [90s]   the same rush against the modern site
  ./lab.sh legacy-deploy              deploy the monolith (stop-start, visible downtime)
  ./lab.sh release good               canary release that passes the checks
  ./lab.sh release bad                canary release with a bug; it is stopped automatically
  ./lab.sh release undo               return booking to v1
  ./lab.sh node-down [0|1]            stop a worker node (0 = the node with the legacy system)
  ./lab.sh node-up [0|1]              start it again

Session 2: site reliability engineering
  ./lab.sh bank slow|errors|down|normal   change the simulated bank
  ./lab.sh chaos list                     list chaos experiments
  ./lab.sh chaos bank-slow                add 3 s network delay to the bank (Chaos Mesh)
  ./lab.sh chaos kill-search              kill one search pod
  ./lab.sh chaos kill-db-primary          kill the database primary (automatic failover)
  ./lab.sh chaos kill-payment-worker      kill all payment workers (queue keeps jobs)
  ./lab.sh chaos stop                     remove all experiments
  ./lab.sh telegram-test                  send a test alert

Between rounds
  ./lab.sh reset                 clear bookings, refill seats, bank back to normal
  ./lab.sh traffic start|stop    background traffic on both sites
EOF
}

ensure_forwarding() {
  # Docker turns IP forwarding on when it starts, but re-applying the system
  # settings can turn it off again (Google Cloud's Ubuntu image sets
  # net.ipv4.ip_forward=0). Without it no container reaches the internet:
  # image builds fail with DNS timeouts and the cluster cannot pull images.
  [ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)" = 1 ] && return 0
  c_warn "IP forwarding was off, so containers could not reach the internet; turning it on"
  sysctl -qw net.ipv4.ip_forward=1 || c_warn "could not turn it on; run: sudo sysctl -w net.ipv4.ip_forward=1"
}

main() {
  local cmd="${1:-help}"; shift || true
  case "$cmd" in help|-h|--help|install-deps) ;; *) ensure_forwarding; ensure_domain;; esac
  case "$cmd" in
    install-deps) cmd_install_deps "$@";;
    up) cmd_up "$@";;
    restart) cmd_restart "$@";;
    boot) cmd_boot "$@";;
    update-ip) cmd_update_ip "$@";;
    update) cmd_update "$@";;
    apply) cmd_apply "$@";;
    down) cmd_down "$@";;
    rebuild) cmd_rebuild "$@";;
    info) cmd_info "$@";;
    status) cmd_status "$@";;
    preflight) cmd_preflight "$@";;
    traffic) cmd_traffic "$@";;
    spike) cmd_spike "$@";;
    bank) cmd_bank "$@";;
    chaos) cmd_chaos "$@";;
    node-down) cmd_node down "$@";;
    node-up) cmd_node up "$@";;
    release) cmd_release "$@";;
    legacy-deploy) cmd_legacy_deploy "$@";;
    reset) cmd_reset "$@";;
    telegram-test) cmd_telegram_test "$@";;
    alerts) cmd_alerts "$@";;
    apply-content) apply_observability_content;;
    help|-h|--help) cmd_help;;
    *) die "unknown command '$cmd'. Try: ./lab.sh help";;
  esac
}
main "$@"
