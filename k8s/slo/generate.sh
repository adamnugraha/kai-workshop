#!/usr/bin/env bash
# Regenerate the Prometheus recording and alerting rules from the SLO specs.
# Needs the sloth CLI: https://github.com/slok/sloth/releases
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p rules
sloth generate -i relnusa-slos.yaml -o rules/relnusa-slo-rules.yaml
echo "rules written to k8s/slo/rules/relnusa-slo-rules.yaml"
