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
source "${SCRIPT_DIR}/cli_dispatch.sh"
source "${SCRIPT_DIR}/http_dispatch.sh"
source "${SCRIPT_DIR}/wait.sh"
source "${SCRIPT_DIR}/logs.sh"

# Inputs via env
NOMAD_ADDR=${NOMAD_ADDR:-}
NOMAD_TOKEN=${NOMAD_TOKEN:-}
JOB_NAME=${JOB_NAME:-}
PAYLOAD=${PAYLOAD:-}
META=${META:-"{}"}
REGION=${REGION:-}
NAMESPACE=${NAMESPACE:-}
TLS_SKIP_VERIFY=${TLS_SKIP_VERIFY:-false}
CA_PEM=${CA_PEM:-}
CLIENT_CERT=${CLIENT_CERT:-}
CLIENT_KEY=${CLIENT_KEY:-}
WAIT=${WAIT:-false}
WAIT_TIMEOUT=${WAIT_TIMEOUT:-300}
PRINT_LOGS=${PRINT_LOGS:-false}
TASK_NAME=${TASK_NAME:-}
DRY_RUN=${DRY_RUN:-false}

# Validate required inputs
require "nomad_addr" "$NOMAD_ADDR"
require "nomad_token" "$NOMAD_TOKEN"
require "job_name" "$JOB_NAME"

# Check for required tools
if ! command -v curl >/dev/null; then err "curl not found"; exit 2; fi
if ! command -v jq >/dev/null; then err "jq not found"; exit 2; fi

# Setup certificates and process meta data
setup_certificates
process_meta

# Determine dispatch method
use_cli=false
if command -v nomad >/dev/null 2>&1; then
  use_cli=true
fi

# Global variables for dispatch results
EVAL_ID=""
DISPATCHED_JOB_ID=""

# Dispatch
if [[ "${use_cli}" == true ]]; then
  if ! dispatch_with_cli; then
    note "Falling back to HTTP API dispatch"
    dispatch_with_http
  fi
else
  dispatch_with_http
fi

# Optionally wait
if [[ "${WAIT}" == "true" ]]; then
  if command -v nomad >/dev/null 2>&1; then
    wait_with_cli || exit $?
  else
    wait_with_http || exit $?
  fi
fi

exit 0
