#!/usr/bin/env bash

# Common functions and utilities for nomad-dispatch

err() { echo "[nomad-dispatch] $*" >&2; }
note() { echo "[nomad-dispatch] $*"; }

require() {
  local name="$1" val="$2"
  if [[ -z "$val" ]]; then err "Missing required input: $name"; exit 2; fi
}

# Global variables for temporary files
TMPDIR="${RUNNER_TEMP:-$(mktemp -d)}"
CACERT_FILE=""
CLIENT_CERT_FILE=""
CLIENT_KEY_FILE=""
