#!/usr/bin/env bash
# One-shot setup on a fresh Ubuntu 22.04/24.04 VM:
#   curl -fsSL https://raw.githubusercontent.com/adamnugraha/kai-workshop/main/bootstrap.sh | sudo bash
# Optional: REPO_URL=... LAB_DIR=... LAB_PROFILE=small (or any other lab.env
# setting) before "sudo bash"; settings are written into lab.env.
# Safe to run again: it updates the code and continues where it stopped.
set -Eeuo pipefail

STEP="start"
step() { STEP="$*"; echo "== $(date -Is) $*"; }

main() {
  REPO_URL="${REPO_URL:-https://github.com/adamnugraha/kai-workshop.git}"
  LAB_DIR="${LAB_DIR:-/opt/kai-workshop}"
  LOG=/var/log/relnusa-lab-install.log

  [ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
  # Cloud boot scripts (EC2 user data, GCE startup scripts) may run without HOME.
  export HOME="${HOME:-/root}"
  # Nothing below needs the terminal. Reading from /dev/null also keeps
  # "curl | bash" safe: no command can swallow the rest of this script.
  exec </dev/null > >(tee -a "$LOG") 2>&1
  trap 'echo "== $(date -Is) FAILED during: $STEP"; echo "== The lines above show why. After fixing it, run again: sudo bash $LAB_DIR/bootstrap.sh"' ERR

  step "RelNusa lab bootstrap (log: $LOG)"
  export DEBIAN_FRONTEND=noninteractive
  step "Base packages"
  apt-get update -q
  apt-get install -y -q git curl ca-certificates >/dev/null

  step "Lab code in $LAB_DIR"
  if [ -d "$LAB_DIR/.git" ]; then
    git -C "$LAB_DIR" pull --ff-only
  else
    git clone "$REPO_URL" "$LAB_DIR"
  fi
  cd "$LAB_DIR"
  git log --oneline -1

  step "Settings in lab.env"
  [ -f lab.env ] || cp lab.env.example lab.env
  # Settings passed in the environment (for example in cloud user data, such as
  # LAB_ACCESS=tunnel or TELEGRAM_BOT_TOKEN=...) are written into lab.env.
  local k v
  for k in LAB_ACCESS LAB_DOMAIN LAB_PUBLIC_IP LAB_HTTPS LAB_ACME_EMAIL LAB_PROFILE HTTP_PORT TRAFFIC_RATE TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID; do
    v="${!k:-}"
    [ -n "$v" ] || continue
    if grep -q "^$k=" lab.env; then sed -i "s|^$k=.*|$k=$v|" lab.env; else echo "$k=$v" >>lab.env; fi
  done

  step "Docker, k3d, kubectl and helm"
  ./lab.sh install-deps

  step "Building and starting the lab (15 to 25 minutes)"
  ./lab.sh up

  step "done. Addresses and login: cd $LAB_DIR && ./lab.sh info"
}

main "$@"
