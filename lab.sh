#!/usr/bin/env bash
# RelNusa availability lab: one command to build, run and demo everything.
# Run "./lab.sh help" for the list of commands.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Everything runs as root, so the cluster, its kubeconfig and the state folder
# always belong to the same user, whoever installed it and whoever presents.
if [ "$(id -u)" -ne 0 ]; then exec sudo -E bash "$ROOT/lab.sh" "$@"; fi
STATE="$ROOT/.lab"
mkdir -p "$STATE"
# Optional settings file (copy lab.env.example to lab.env).
if [ -f "$ROOT/lab.env" ]; then set -a; . "$ROOT/lab.env"; set +a; fi

CLUSTER="${CLUSTER:-relnusa}"
LAB_DOMAIN="${LAB_DOMAIN:-localhost}"
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
# Host ports on 127.0.0.1 (change them if the server already uses 80 or 9090;
# they are fixed when the cluster is created)
HTTP_PORT="${HTTP_PORT:-80}"
PROM_PORT="${PROM_PORT:-9090}"
DOCKER_BUILD_FLAGS="${DOCKER_BUILD_FLAGS:-}"

if [ "$LAB_PROFILE" = "small" ]; then DB_INSTANCES="${DB_INSTANCES:-2}"; else DB_INSTANCES="${DB_INSTANCES:-3}"; fi
if [ "$DB_INSTANCES" -gt 1 ]; then SEARCH_DB_HOST=relnusa-db-ro; else SEARCH_DB_HOST=relnusa-db-rw; fi

c_info() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
c_ok()   { printf '\033[1;32m ok\033[0m %s\n' "$*"; }
c_warn() { printf '\033[1;33m !!\033[0m %s\n' "$*"; }
die()    { printf '\033[1;31mERROR\033[0m %s\n' "$*" >&2; exit 1; }
need()   { command -v "$1" >/dev/null 2>&1 || die "'$1' is not installed. Run: sudo ./lab.sh install-deps"; }

arch() { case "$(uname -m)" in x86_64|amd64) echo amd64;; aarch64|arm64) echo arm64;; *) die "unsupported CPU $(uname -m)";; esac; }

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
    apt-get update -q
    apt-get install -y -q curl ca-certificates git jq tar gzip >/dev/null
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
ports:
  - port: 127.0.0.1:$HTTP_PORT:80
    nodeFilters: [server:0:direct]
  - port: 127.0.0.1:$PROM_PORT:30090
    nodeFilters: [server:0:direct]
options:
  k3d:
    wait: true
    timeout: "300s"
  k3s:
    extraArgs:
      - arg: --kube-controller-manager-arg=node-monitor-grace-period=20s
        nodeFilters: [server:*]
    nodeLabels:
      - label: topology.kubernetes.io/zone=zona-a
        nodeFilters: [server:0]
      - label: topology.kubernetes.io/zone=zona-b
        nodeFilters: [agent:0]
      - label: lab.relnusa.io/legacy=true
        nodeFilters: [agent:0]
      - label: topology.kubernetes.io/zone=zona-c
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

cluster_exists() { k3d cluster list -o json 2>/dev/null | grep "\"name\":\"$CLUSTER\"" >/dev/null; }

build_image() {
  local img; img="$(image_ref)"
  echo "$img" >"$STATE/image"
  if docker image inspect "$img" >/dev/null 2>&1; then
    c_ok "image $img already built"
  else
    c_info "Building application image $img"
    # shellcheck disable=SC2086
    docker build $DOCKER_BUILD_FLAGS -t "$img" "$ROOT/app"
  fi
  if cluster_exists; then
    c_info "Loading image into the cluster nodes"
    local n
    for n in 1 2 3; do
      k3d image import "$img" -c "$CLUSTER" >/dev/null 2>&1 || true
      image_on_all_nodes "$img" && return 0
      c_warn "image import incomplete (attempt $n), retrying"
      sleep 3
    done
    die "could not load $img into every node; run ./lab.sh rebuild again"
  fi
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
    write_k3d_config
    c_info "Creating 3-node Kubernetes cluster (1 control plane + 2 workers)"
    k3d cluster create --config "$STATE/k3d.yaml"
  fi
  kubectl config use-context "k3d-$CLUSTER" >/dev/null
  kubectl apply -f "$ROOT/k8s/cluster/traefik-config.yaml" >/dev/null
  pin_system_pods
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
  apply_observability_content
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
  local d
  for d in "$ROOT/k8s/slo/rules" "$ROOT/k8s/dashboards"; do
    if ls "$d"/*.yaml >/dev/null 2>&1; then kubectl apply -f "$d/" >/dev/null; fi
  done
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
  c_ok "lab is up in $(( ($(date +%s) - start) / 60 )) minutes"
  cmd_info
}

cmd_rebuild() {
  build_image
  roll_app_pods
  c_ok "application pods are rolling to $(cat "$STATE/image")"
}

cmd_down() {
  cmd_traffic stop || true
  k3d cluster delete "$CLUSTER"
}

# ---------------------------------------------------------------- traffic
k6_run() {
  # shellcheck disable=SC2068
  docker run --rm --network host -v "$ROOT/load:/scripts:ro" \
    -e K6_PROMETHEUS_RW_SERVER_URL="http://127.0.0.1:$PROM_PORT/api/v1/write" \
    -e K6_PROMETHEUS_RW_TREND_STATS="p(95),p(99),avg" \
    -e K6_PROMETHEUS_RW_PUSH_INTERVAL=5s \
    -e HTTP_PORT="$HTTP_PORT" \
    $@
}

cmd_traffic() {
  case "${1:-status}" in
    start)
      docker rm -f relnusa-traffic >/dev/null 2>&1 || true
      docker run -d --name relnusa-traffic --restart unless-stopped --network host \
        -v "$ROOT/load:/scripts:ro" \
        -e K6_PROMETHEUS_RW_SERVER_URL="http://127.0.0.1:$PROM_PORT/api/v1/write" \
        -e HTTP_PORT="$HTTP_PORT" \
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
  c_info "War tiket against the $target site: up to $peak new buyers per second for $hold"
  k6_run -e TARGET="$target" -e PEAK_RATE="$peak" -e HOLD="$hold" "$K6_IMAGE" run --out experimental-prometheus-rw /scripts/war-tiket.js
}

# ---------------------------------------------------------------- faults
bank_api() { curl -fsS -X "$1" -H "Host: bank.$LAB_DOMAIN" "http://127.0.0.1:$HTTP_PORT/admin/config${2:-}"; echo; }

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
  kubectl delete -f "$ROOT/chaos/" --ignore-not-found --wait=false >/dev/null 2>&1 || true
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
  local action="$1" n="${2:-0}" name="k3d-$CLUSTER-agent-${2:-0}"
  case "$action" in
    down)
      pin_system_pods
      if [ "${KEEP_DB_PRIMARY:-yes}" = yes ]; then cmd_db_primary_away "$name"; fi
      c_info "Stopping node $name (zona-$([ "$n" = 0 ] && echo b || echo c))"
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
  curl -fsS -X POST -H "Host: alertmanager.$LAB_DOMAIN" -H 'Content-Type: application/json' \
    "http://127.0.0.1:$HTTP_PORT/api/v2/alerts" -d "[{\"labels\":{\"alertname\":\"UjiNotifikasi\",\"sloth_service\":\"relnusa-modern\",\"sloth_slo\":\"uji\",\"severity\":\"info\"},\"annotations\":{\"title\":\"Uji jalur peringatan\",\"summary\":\"Jika pesan ini masuk, peringatan dari lab sudah sampai ke Telegram.\"},\"startsAt\":\"$now\"}]"
  c_ok "test alert sent to Alertmanager (arrives in Telegram within about 15 seconds if configured)"
}

cmd_info() {
  local ip; ip="$(curl -fsS -m 3 https://checkip.amazonaws.com 2>/dev/null || hostname -I | awk '{print $1}')"
  cat <<EOF

RelNusa lab ($LAB_PROFILE profile). From your laptop, open an SSH tunnel:

  ssh -N -L 8080:127.0.0.1:$HTTP_PORT -L 9090:127.0.0.1:$PROM_PORT <user>@$ip

then browse (Chrome or Edge resolve *.localhost automatically):

  Legacy site       http://legacy.$LAB_DOMAIN:8080
  Modern site       http://app.$LAB_DOMAIN:8080
  Grafana           http://grafana.$LAB_DOMAIN:8080   (admin / $(grafana_password))
  Jaeger traces     http://jaeger.$LAB_DOMAIN:8080
  Chaos Mesh        http://chaos.$LAB_DOMAIN:8080
  Argo Rollouts     http://rollouts.$LAB_DOMAIN:8080
  Prometheus        http://prometheus.$LAB_DOMAIN:8080
  Alertmanager      http://alertmanager.$LAB_DOMAIN:8080

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
    v="$(curl -s -m 5 -o /dev/null -w '%{http_code}' -H "Host: $h.$LAB_DOMAIN" "http://127.0.0.1:$HTTP_PORT/" 2>/dev/null)"
    [ "$v" = 200 ] || [ "$v" = 302 ] && c_ok "http://$h.$LAB_DOMAIN:8080 answers ($v)" || fail "http://$h.$LAB_DOMAIN:8080 answers $v"
  done

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

  if [ -d /sys/module/sch_netem ] || modprobe -n sch_netem 2>/dev/null; then c_ok "kernel supports network delay (chaos bank-lambat)"
  else c_warn "no netem module: use ./lab.sh bank slow instead of ./lab.sh chaos bank-lambat"; fi

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
  ./lab.sh info                  URLs, password and the SSH tunnel command
  ./lab.sh status                nodes, pods, database primary, traffic, bank mode
  ./lab.sh preflight             check everything before going on stage
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
  ./lab.sh chaos bank-lambat              add 3 s network delay to the bank (Chaos Mesh)
  ./lab.sh chaos matikan-search           kill one search pod
  ./lab.sh chaos matikan-db-primary       kill the database primary (automatic failover)
  ./lab.sh chaos matikan-payment-worker   kill all payment workers (queue keeps jobs)
  ./lab.sh chaos stop                     remove all experiments
  ./lab.sh telegram-test                  send a test alert

Between rounds
  ./lab.sh reset                 clear bookings, refill seats, bank back to normal
  ./lab.sh traffic start|stop    background traffic on both sites
EOF
}

main() {
  local cmd="${1:-help}"; shift || true
  case "$cmd" in
    install-deps) cmd_install_deps "$@";;
    up) cmd_up "$@";;
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
