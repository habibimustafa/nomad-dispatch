#!/usr/bin/env bash

# HTTP API dispatch functionality

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

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
