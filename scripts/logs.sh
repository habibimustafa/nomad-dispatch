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
      nomad "${NOMAD_ARGS[@]}" alloc logs -no-color -stdout "${aid}" "${TASK_NAME}" || true
      echo
      echo "===== ${aid} stderr ====="
      nomad "${NOMAD_ARGS[@]}" alloc logs -no-color -stderr "${aid}" "${TASK_NAME}" || true
      echo
    done
  fi
}

fetch_logs_with_http() {
  local ALLOC_IDS=("$@")
  local CURL_ARGS=("-sS" "-H" "X-Nomad-Token: ${NOMAD_TOKEN}" "-H" "Content-Type: application/json")
  [[ -n "${REGION}" ]] && CURL_ARGS+=("-H" "X-Nomad-Region: ${REGION}")
  [[ -n "${NAMESPACE}" ]] && CURL_ARGS+=("-H" "X-Nomad-Namespace: ${NAMESPACE}")
  [[ "${TLS_SKIP_VERIFY}" == "true" ]] && CURL_ARGS+=("-k")
  [[ -n "${CACERT_FILE}" ]] && CURL_ARGS+=("--cacert" "${CACERT_FILE}")
  [[ -n "${CLIENT_CERT_FILE}" ]] && CURL_ARGS+=("--cert" "${CLIENT_CERT_FILE}")
  [[ -n "${CLIENT_KEY_FILE}" ]] && CURL_ARGS+=("--key" "${CLIENT_KEY_FILE}")

  if [[ "${PRINT_LOGS}" == "true" && -n "${TASK_NAME}" ]]; then
    note "Fetching logs for task '${TASK_NAME}' via HTTP API"
    for aid in "${ALLOC_IDS[@]}"; do
      local base="${NOMAD_ADDR%/}/v1/client/fs/logs/${aid}?task=${TASK_NAME}&follow=false&plain=true"
      echo "===== ${aid} stdout ====="
      curl -sS "${CURL_ARGS[@]}" "${base}&type=stdout" || true
      echo
      echo "===== ${aid} stderr ====="
      curl -sS "${CURL_ARGS[@]}" "${base}&type=stderr" || true
      echo
    done
  fi
}
