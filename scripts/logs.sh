#!/usr/bin/env bash

# Log fetching functionality

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

fetch_logs_with_cli() {
  local ALLOC_IDS=("$@")
  local NOMAD_ARGS=(
    "-address=${NOMAD_ADDR}"
    "-token=${NOMAD_TOKEN}"
  )
  [[ -n "${REGION}" ]] && NOMAD_ARGS+=("-region=${REGION}")
  [[ -n "${NAMESPACE}" ]] && NOMAD_ARGS+=("-namespace=${NAMESPACE}")
  [[ -n "${CACERT_FILE}" ]] && NOMAD_ARGS+=("-ca-cert=${CACERT_FILE}")
  [[ -n "${CLIENT_CERT_FILE}" ]] && NOMAD_ARGS+=("-client-cert=${CLIENT_CERT_FILE}")
  [[ -n "${CLIENT_KEY_FILE}" ]] && NOMAD_ARGS+=("-client-key=${CLIENT_KEY_FILE}")
  [[ "${TLS_SKIP_VERIFY}" == "true" ]] && NOMAD_ARGS+=("-tls-skip-verify")

  if [[ "${PRINT_LOGS}" == "true" && -n "${TASK_NAME}" ]]; then
    note "Fetching logs for task '${TASK_NAME}' via Nomad CLI"
    for aid in "${ALLOC_IDS[@]}"; do
      echo "===== ${aid} stdout ====="
      nomad alloc logs "${NOMAD_ARGS[@]}" -no-color -stdout "${aid}" "${TASK_NAME}" || true
      echo
      echo "===== ${aid} stderr ====="
      nomad alloc logs "${NOMAD_ARGS[@]}" -no-color -stderr "${aid}" "${TASK_NAME}" || true
      echo
    done
  fi
}

