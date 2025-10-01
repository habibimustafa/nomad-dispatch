#!/usr/bin/env bash

# Wait and allocation monitoring functionality

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

wait_dispatch() {
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

  # Fetch logs if requested
  fetch_logs_with_cli "${ALLOC_IDS[@]}"
}

