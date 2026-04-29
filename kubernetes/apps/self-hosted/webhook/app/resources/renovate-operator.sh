#!/usr/bin/env bash
set -euo pipefail

# this basically just directly forwards the events
# this allows using the renovate-operator's github webhook support,
# without having to expose the operator as external

# Incoming arguments
JOB=${1:-}
NAMESPACE=${2:-}
BODY=${3:-}

# in github webhooks, enable: pull requests and issues
curl -s -X POST \
  "http://renovate-operator.renovate.svc.cluster.local:8082/webhook/v1/github?job=${JOB}&namespace=${NAMESPACE}" \
  -H "Content-Type: application/json" \
  --data-raw "${BODY}"
