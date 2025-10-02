#!/usr/bin/env bash

# Nomad CLI dispatch functionality

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

run_dispatch() {
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
    note "dry_run=true; would run: nomad job dispatch ${NOMAD_ARGS[*]} ${META_ARGS[*]} ${JOB_NAME} ${PAYLOAD:+-}"
    echo "status=dispatched" >>"${GITHUB_OUTPUT}"
    return 0
  fi

  note "Dispatching with Nomad CLI to ${NOMAD_ADDR}"
  if [[ -n "${PAYLOAD}" ]]; then
    set +e
    out=$(printf '%s' "${PAYLOAD}" | nomad job dispatch "${NOMAD_ARGS[@]}" "${META_ARGS[@]}" "${JOB_NAME}" - 2>&1)
    rc=$?
    set -e
  else
    set +e
    out=$(nomad job dispatch "${NOMAD_ARGS[@]}" "${META_ARGS[@]}" "${JOB_NAME}" 2>&1)
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
