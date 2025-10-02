#!/usr/bin/env bash
set -euo pipefail

# Main orchestration script for nomad-dispatch
# Sources modular components and coordinates their execution

# Get script directory for sourcing modules
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"

# Source all modules
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/certificates.sh"
source "${SCRIPT_DIR}/meta.sh"
source "${SCRIPT_DIR}/oidc.sh"
source "${SCRIPT_DIR}/dispatcher.sh"
source "${SCRIPT_DIR}/logs.sh"

# Inputs via env
NOMAD_ADDR=${NOMAD_ADDR:-}
NOMAD_TOKEN=${NOMAD_TOKEN:-}
OIDC_ENABLE=${OIDC_ENABLE:-false}
OIDC_AUDIENCE=${OIDC_AUDIENCE:-nomad.example.com}
OIDC_DEBUG=${OIDC_DEBUG:-false}
JOB_NAME=${JOB_NAME:-}
PAYLOAD=${PAYLOAD:-}
META=${META:-"{}"}
REGION=${REGION:-}
NAMESPACE=${NAMESPACE:-}
TLS_SKIP_VERIFY=${TLS_SKIP_VERIFY:-false}
CA_PEM=${CA_PEM:-}
CLIENT_CERT=${CLIENT_CERT:-}
CLIENT_KEY=${CLIENT_KEY:-}
LIVE_LOGS=${LIVE_LOGS:-true}
STREAM_TIMEOUT=${STREAM_TIMEOUT:-300}
AUTO_CLOSE_ON_COMPLETE=${AUTO_CLOSE_ON_COMPLETE:-true}
TASK_NAME=${TASK_NAME:-}
DRY_RUN=${DRY_RUN:-false}
DISPATCH_DEBUG=${DISPATCH_DEBUG:-false}

# Validate required inputs
require "nomad_addr" "$NOMAD_ADDR"
require "job_name" "$JOB_NAME"

# Check for required tools
if ! command -v curl >/dev/null; then err "curl not found"; exit 2; fi
if ! command -v jq >/dev/null; then err "jq not found"; exit 2; fi

# Setup certificates and process meta data
setup_certificates
process_meta

# Get OIDC token if enabled, otherwise validate provided token
get_oidc_token
if [[ -z "$NOMAD_TOKEN" ]]; then
  err "nomad_token is required when OIDC authentication is disabled"
  exit 2
fi

# Check for Nomad CLI availability
if ! command -v nomad >/dev/null 2>&1; then
  err "nomad CLI not found - this should not happen as it's installed by setup-nomad"
  exit 2
fi

# Global variables for dispatch results
EVAL_ID=""
DISPATCHED_JOB_ID=""

# Dispatching the job
run_dispatch

exit 0
