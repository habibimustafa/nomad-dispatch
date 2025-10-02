#!/usr/bin/env bash

# Log fetching functionality

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

stream_live_logs() {
  if [[ "${LIVE_LOGS}" != "true" || -z "${TASK_NAME}" ]]; then
    return 0
  fi

  # Wait for allocations to be available and start monitoring
  local timeout=30
  local elapsed=0
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

  note "Starting live log streaming for task '${TASK_NAME}'"
  while (( elapsed < timeout )); do
    local EV_JSON
    if EV_JSON=$(nomad eval status "${NOMAD_ARGS[@]}" -json "${EVAL_ID}" 2>/dev/null); then
      local ALLOC_IDS
      mapfile -t ALLOC_IDS < <(printf '%s' "${EV_JSON}" | jq -r '.Allocations // [] | .[] | .ID')
      if (( ${#ALLOC_IDS[@]} > 0 )); then
        # Stream logs from first available allocation
        local aid="${ALLOC_IDS[0]}"
        note "Streaming live logs from allocation ${aid}"
        stream_logs_with_monitoring "${aid}" "${NOMAD_ARGS[@]}"
        break
      fi
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  if (( elapsed >= timeout )); then
    note "Timeout waiting for allocations to become available for live logging"
  fi
}

stream_logs_with_monitoring() {
  local aid="$1"
  shift
  local NOMAD_ARGS=("$@")

  # Create named pipes for communication
  local log_pipe="${TMPDIR%/}/nomad_logs_$$"
  local monitor_pipe="${TMPDIR%/}/nomad_monitor_$$"
  mkfifo "${log_pipe}" "${monitor_pipe}" 2>/dev/null || true

  # Cleanup function
  cleanup_streaming() {
    local log_pid="$1"
    local monitor_pid="$2"

    # Kill background processes
    [[ -n "${log_pid}" ]] && kill "${log_pid}" 2>/dev/null || true
    [[ -n "${monitor_pid}" ]] && kill "${monitor_pid}" 2>/dev/null || true

    # Clean up pipes
    rm -f "${log_pipe}" "${monitor_pipe}" 2>/dev/null || true

    note "Log streaming terminated"
  }

  # Start log streaming in background
  nomad alloc logs "${NOMAD_ARGS[@]}" -follow -no-color "${aid}" "${TASK_NAME}" > "${log_pipe}" 2>&1 &
  local log_pid=$!

  # Start allocation monitoring in background if auto-close is enabled
  local monitor_pid=""
  if [[ "${AUTO_CLOSE_ON_COMPLETE}" == "true" ]]; then
    (
      while true; do
        local alloc_json
        if alloc_json=$(nomad alloc status "${NOMAD_ARGS[@]}" -json "${aid}" 2>/dev/null); then
          local status
          status=$(echo "${alloc_json}" | jq -r '.ClientStatus // "unknown"')
          case "$status" in
            complete|failed|lost)
              echo "ALLOCATION_COMPLETE:$status" > "${monitor_pipe}"
              exit 0
              ;;
          esac
        fi
        sleep 5
      done
    ) &
    monitor_pid=$!
  fi

  # Handle log output and monitoring
  local last_activity=$(date +%s)
  local stream_timeout_seconds="${STREAM_TIMEOUT}"

  # Set up signal handlers for cleanup
  trap "cleanup_streaming '${log_pid}' '${monitor_pid}'" EXIT INT TERM

  while true; do
    local current_time=$(date +%s)

    # Check for inactivity timeout (if enabled)
    if [[ "${stream_timeout_seconds}" -gt 0 ]]; then
      local idle_time=$((current_time - last_activity))
      if [[ "${idle_time}" -ge "${stream_timeout_seconds}" ]]; then
        note "Stream timeout reached (${stream_timeout_seconds}s of inactivity)"
        break
      fi
    fi

    # Check for allocation completion (if monitoring enabled)
    if [[ -n "${monitor_pid}" ]] && read -t 1 -r completion_msg < "${monitor_pipe}" 2>/dev/null; then
      if [[ "${completion_msg}" =~ ^ALLOCATION_COMPLETE: ]]; then
        local final_status="${completion_msg#ALLOCATION_COMPLETE:}"
        note "Allocation completed with status: ${final_status}"
        break
      fi
    fi

    # Read and display log output with timeout
    if read -t 1 -r log_line < "${log_pipe}" 2>/dev/null; then
      echo "${log_line}"
      last_activity=$(date +%s)
    fi

    # Check if log process is still running
    if ! kill -0 "${log_pid}" 2>/dev/null; then
      note "Log streaming process ended"
      break
    fi
  done

  # Cleanup will be handled by trap
}


