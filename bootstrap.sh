#!/usr/bin/env bash
# One-shot setup on a fresh Ubuntu 22.04/24.04 VM:
#   curl -fsSL https://raw.githubusercontent.com/adamnugraha/kai-workshop/main/bootstrap.sh | sudo bash
# Optional: REPO_URL=... LAB_DIR=... LAB_PROFILE=small before "sudo bash".
set -euo pipefail
REPO_URL="${REPO_URL:-https://github.com/adamnugraha/kai-workshop.git}"
LAB_DIR="${LAB_DIR:-/opt/kai-workshop}"
LOG=/var/log/relnusa-lab-install.log

[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
# Cloud boot scripts (EC2 user data, GCE startup scripts) may run without HOME.
export HOME="${HOME:-/root}"
exec > >(tee -a "$LOG") 2>&1
echo "== $(date -Is) RelNusa lab bootstrap"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q git curl ca-certificates >/dev/null
if [ -d "$LAB_DIR/.git" ]; then
  git -C "$LAB_DIR" pull --ff-only
else
  git clone "$REPO_URL" "$LAB_DIR"
fi
cd "$LAB_DIR"
[ -f lab.env ] || cp lab.env.example lab.env
./lab.sh install-deps
./lab.sh up
echo "== $(date -Is) done. Run: cd $LAB_DIR && ./lab.sh info"
