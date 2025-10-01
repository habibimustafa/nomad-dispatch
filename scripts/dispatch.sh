#!/usr/bin/env bash
set -euo pipefail

# Inputs via env
NOMAD_ADDR=${NOMAD_ADDR:-}
NOMAD_TOKEN=${NOMAD_TOKEN:-}
JOB_NAME=${JOB_NAME:-}
PAYLOAD=${PAYLOAD:-}
META_JSON=${META_JSON:-"{}"}
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

err() { echo "[nomad-dispatch] $*" >&2; }
note() { echo "[nomad-dispatch] $*"; }

require() {
  local name="$1" val="$2"
  if [[ -z "$val" ]]; then err "Missing required input: $name"; exit 2; fi
}

require "nomad_addr" "$NOMAD_ADDR"
require "nomad_token" "$NOMAD_TOKEN"
require "job_name" "$JOB_NAME"

if ! command -v curl >/dev/null; then err "curl not found"; exit 2; fi
if ! command -v jq >/dev/null; then err "jq not found"; exit 2; fi

TMPDIR="${RUNNER_TEMP:-$(mktemp -d)}"
CACERT_FILE=""
CLIENT_CERT_FILE=""
CLIENT_KEY_FILE=""

# Build common TLS/auth artifacts
if [[ -n "${CA_PEM}" ]]; then
  CACERT_FILE="${TMPDIR%/}/nomad-ca.pem"
  printf "%s" "${CA_PEM}" > "${CACERT_FILE}"
fi

if [[ -n "${CLIENT_CERT}" ]]; then
  CLIENT_CERT_FILE="${TMPDIR%/}/nomad-client.crt"
  printf "%s" "${CLIENT_CERT}" > "${CLIENT_CERT_FILE}"
fi

if [[ -n "${CLIENT_KEY}" ]]; then
  CLIENT_KEY_FILE="${TMPDIR%/}/nomad-client.key"
  printf "%s" "${CLIENT_KEY}" > "${CLIENT_KEY_FILE}"
fi

# Prepare meta as key=value array for CLI and JSON for HTTP
if ! echo "${META_JSON}" | jq -e 'type=="object"' >/dev/null 2>&1; then
  err "meta_json must be a valid JSON object"
  exit 2
fi
readarray -t META_KV < <(echo "${META_JSON}" | jq -r 'to_entries[] | "\(.key)=\(.value|tostring)"' 2>/dev/null || true)

# Try Nomad CLI first
use_cli=false
if command -v nomad >/dev/null 2>&1; then
  use_cli=true
fi

dispatch_with_cli() {
  local out rc=0
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

  local META_ARGS=()
  if (( ${#META_KV[@]} > 0 )); then
    for kv in "${META_KV[@]}"; do META_ARGS+=("-meta" "$kv"); done
  fi

  if [[ "${DRY_RUN}" == "true" ]]; then
    note "dry_run=true; would run: nomad job dispatch ${META_ARGS[*]} ${JOB_NAME} ${PAYLOAD:+-}"
    echo "status=dispatched" >>"${GITHUB_OUTPUT}"
    return 0
  fi

  note "Dispatching with Nomad CLI to ${NOMAD_ADDR}"
  if [[ -n "${PAYLOAD}" ]]; then
    set +e
    out=$(printf '%s' "${PAYLOAD}" | nomad "${NOMAD_ARGS[@]}" job dispatch "${META_ARGS[@]}" "${JOB_NAME}" - 2>&1)
    rc=$?
    set -e
  else
    set +e
    out=$(nomad "${NOMAD_ARGS[@]}" job dispatch "${META_ARGS[@]}" "${JOB_NAME}" 2>&1)
    rc=$?
    set -e
  fi
  if (( rc != 0 )); then
    err "nomad job dispatch failed (rc=${rc}): ${out}"
    return ${rc}
  fi

  # Parse output for EvalID and DispatchedJobID
  EVAL_ID=$(echo "${out}" | sed -n 's/^Evaluation ID: *//p' | head -n1)
  DISPATCHED_JOB_ID=$(echo "${out}" | sed -n 's/^Dispatched Job ID: *//p' | head -n1)
  if [[ -z "${EVAL_ID}" ]]; then
    # Try alternative formatting
    EVAL_ID=$(echo "${out}" | grep -Eo '[0-9a-f-]{36}' | head -n1 || true)
  fi
  if [[ -z "${EVAL_ID}" ]]; then
    err "Could not parse EvalID from nomad CLI output"
    return 1
  fi

  echo "dispatched_job_id=${DISPATCHED_JOB_ID}" >>"${GITHUB_OUTPUT}"
  echo "eval_id=${EVAL_ID}" >>"${GITHUB_OUTPUT}"
  echo "status=dispatched" >>"${GITHUB_OUTPUT}"
  note "Dispatched EvalID=${EVAL_ID} DispatchedJobID=${DISPATCHED_JOB_ID}"
  return 0
}

dispatch_with_http() {
  # Build curl args
  local CURL_ARGS=("-sS" "-H" "X-Nomad-Token: ${NOMAD_TOKEN}" "-H" "Content-Type: application/json")
  [[ -n "${REGION}" ]] && CURL_ARGS+=("-H" "X-Nomad-Region: ${REGION}")
  [[ -n "${NAMESPACE}" ]] && CURL_ARGS+=("-H" "X-Nomad-Namespace: ${NAMESPACE}")
  [[ "${TLS_SKIP_VERIFY}" == "true" ]] && CURL_ARGS+=("-k")
  [[ -n "${CACERT_FILE}" ]] && CURL_ARGS+=("--cacert" "${CACERT_FILE}")
  [[ -n "${CLIENT_CERT_FILE}" ]] && CURL_ARGS+=("--cert" "${CLIENT_CERT_FILE}")
  [[ -n "${CLIENT_KEY_FILE}" ]] && CURL_ARGS+=("--key" "${CLIENT_KEY_FILE}")

  local PAYLOAD_B64=""
  if [[ -n "${PAYLOAD}" ]]; then
    if base64 --help 2>&1 | grep -q "-w"; then
      PAYLOAD_B64=$(printf '%s' "${PAYLOAD}" | base64 -w0)
    else
      PAYLOAD_B64=$(printf '%s' "${PAYLOAD}" | base64)
    fi
  fi

  local BODY
  BODY=$(jq -nc \
    --arg p "${PAYLOAD_B64}" \
    --argjson m "${META_JSON}" \
    ' (if ($p|length)>0 then {Payload:$p} else {} end)
      + (if ($m|type)=="object" then {Meta:$m} else {} end) ')

  local DISPATCH_URL="${NOMAD_ADDR%/}/v1/job/${JOB_NAME}/dispatch"
  if [[ "${DRY_RUN}" == "true" ]]; then
    note "dry_run=true; would POST to ${DISPATCH_URL} with body: ${BODY}"
    echo "status=dispatched" >>"${GITHUB_OUTPUT}"
    return 0
  fi

  note "Dispatching with HTTP API to ${NOMAD_ADDR}"
  local RESP HTTP_CODE JSON
  RESP=$(curl -w "\n%{http_code}" -X POST "${CURL_ARGS[@]}" -d "${BODY}" "${DISPATCH_URL}") || true
  HTTP_CODE=$(printf '%s' "${RESP}" | tail -n1)
  JSON=$(printf '%s' "${RESP}" | sed '$d')
  if [[ "${HTTP_CODE}" -lt 200 || "${HTTP_CODE}" -ge 300 ]]; then
    err "Dispatch failed (HTTP ${HTTP_CODE}): ${JSON}"
    return 1
  fi
  DISPATCHED_JOB_ID=$(printf '%s' "${JSON}" | jq -r '.DispatchedJobID // empty')
  EVAL_ID=$(printf '%s' "${JSON}" | jq -r '.EvalID // empty')
  if [[ -z "${EVAL_ID}" ]]; then
    err "No EvalID in response: ${JSON}"
    return 1
  fi
  echo "dispatched_job_id=${DISPATCHED_JOB_ID}" >>"${GITHUB_OUTPUT}"
  echo "eval_id=${EVAL_ID}" >>"${GITHUB_OUTPUT}"
  echo "status=dispatched" >>"${GITHUB_OUTPUT}"
  note "Dispatched EvalID=${EVAL_ID} DispatchedJobID=${DISPATCHED_JOB_ID}"
  return 0
}

wait_with_cli() {
  local deadline=$(( $(date +%s) + WAIT_TIMEOUT ))
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

  local ALLOC_IDS=()
  while true; do
    local now=$(date +%s)
    if (( now > deadline )); then
      err "Timeout waiting for allocations"
      echo "status=timeout" >>"${GITHUB_OUTPUT}"
      echo "alloc_ids=[]" >>"${GITHUB_OUTPUT}"
      return 124
    fi
    local EV_JSON
    if ! EV_JSON=$(nomad "${NOMAD_ARGS[@]}" eval status -json "${EVAL_ID}" 2>/dev/null); then
      sleep 2; continue
    fi
    mapfile -t ALLOC_IDS < <(printf '%s' "${EV_JSON}" | jq -r '.Allocations // [] | .[] | .ID')
    if (( ${#ALLOC_IDS[@]} == 0 )); then sleep 2; continue; fi

    local all_complete=true any_failed=false
    for aid in "${ALLOC_IDS[@]}"; do
      local AJSON
      if ! AJSON=$(nomad "${NOMAD_ARGS[@]}" alloc status -json "${aid}" 2>/dev/null); then all_complete=false; break; fi
      local cstatus dstatus
      cstatus=$(printf '%s' "${AJSON}" | jq -r '.ClientStatus // "unknown"')
      dstatus=$(printf '%s' "${AJSON}" | jq -r '.DesiredStatus // ""')
      case "$cstatus" in
        complete) ;;
        failed|lost) any_failed=true ;;
        *) all_complete=false ;;
      esac
      if [[ "$dstatus" == "stop" && "$cstatus" != "complete" ]]; then any_failed=true; fi
    done

    if [[ "$any_failed" == true ]]; then
      echo "alloc_ids=$(printf '%s' "${ALLOC_IDS[@]}" | jq -R -s 'split("\n")[:-1]')" >>"${GITHUB_OUTPUT}"
      echo "status=failed" >>"${GITHUB_OUTPUT}"
      err "One or more allocations failed"
      return 1
    fi
    if [[ "$all_complete" == true ]]; then
      echo "alloc_ids=$(printf '%s' "${ALLOC_IDS[@]}" | jq -R -s 'split("\n")[:-1]')" >>"${GITHUB_OUTPUT}"
      echo "status=complete" >>"${GITHUB_OUTPUT}"
      note "All allocations complete"
      break
    fi
    sleep 2
  done

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

wait_with_http() {
  local deadline=$(( $(date +%s) + WAIT_TIMEOUT ))
  local CURL_ARGS=("-sS" "-H" "X-Nomad-Token: ${NOMAD_TOKEN}" "-H" "Content-Type: application/json")
  [[ -n "${REGION}" ]] && CURL_ARGS+=("-H" "X-Nomad-Region: ${REGION}")
  [[ -n "${NAMESPACE}" ]] && CURL_ARGS+=("-H" "X-Nomad-Namespace: ${NAMESPACE}")
  [[ "${TLS_SKIP_VERIFY}" == "true" ]] && CURL_ARGS+=("-k")
  [[ -n "${CACERT_FILE}" ]] && CURL_ARGS+=("--cacert" "${CACERT_FILE}")
  [[ -n "${CLIENT_CERT_FILE}" ]] && CURL_ARGS+=("--cert" "${CLIENT_CERT_FILE}")
  [[ -n "${CLIENT_KEY_FILE}" ]] && CURL_ARGS+=("--key" "${CLIENT_KEY_FILE}")

  local ALLOC_IDS=()
  local eval_url="${NOMAD_ADDR%/}/v1/eval/${EVAL_ID}"
  local alloc_url_base="${NOMAD_ADDR%/}/v1/allocation"
  while true; do
    local now=$(date +%s)
    if (( now > deadline )); then
      err "Timeout waiting for allocations"
      echo "status=timeout" >>"${GITHUB_OUTPUT}"
      echo "alloc_ids=[]" >>"${GITHUB_OUTPUT}"
      return 124
    fi
    local EV_JSON
    EV_JSON=$(curl -sS "${CURL_ARGS[@]}" "${eval_url}") || { sleep 2; continue; }
    mapfile -t ALLOC_IDS < <(printf '%s' "${EV_JSON}" | jq -r '.Allocations // [] | .[] | .ID')
    if (( ${#ALLOC_IDS[@]} == 0 )); then sleep 2; continue; fi

    local all_complete=true any_failed=false
    for aid in "${ALLOC_IDS[@]}"; do
      local AJSON
      AJSON=$(curl -sS "${CURL_ARGS[@]}" "${alloc_url_base}/${aid}") || { all_complete=false; break; }
      local cstatus dstatus
      cstatus=$(printf '%s' "${AJSON}" | jq -r '.ClientStatus // "unknown"')
      dstatus=$(printf '%s' "${AJSON}" | jq -r '.DesiredStatus // ""')
      case "$cstatus" in
        complete) ;;
        failed|lost) any_failed=true ;;
        *) all_complete=false ;;
      esac
      if [[ "$dstatus" == "stop" && "$cstatus" != "complete" ]]; then any_failed=true; fi
    done
    if [[ "$any_failed" == true ]]; then
      echo "alloc_ids=$(printf '%s' "${ALLOC_IDS[@]}" | jq -R -s 'split("\n")[:-1]')" >>"${GITHUB_OUTPUT}"
      echo "status=failed" >>"${GITHUB_OUTPUT}"
      err "One or more allocations failed"
      return 1
    fi
    if [[ "$all_complete" == true ]]; then
      echo "alloc_ids=$(printf '%s' "${ALLOC_IDS[@]}" | jq -R -s 'split("\n")[:-1]')" >>"${GITHUB_OUTPUT}"
      echo "status=complete" >>"${GITHUB_OUTPUT}"
      note "All allocations complete"
      break
    fi
    sleep 2
  done

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
