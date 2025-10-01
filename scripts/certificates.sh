#!/usr/bin/env bash

# Certificate and TLS file management for nomad-dispatch

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

setup_certificates() {
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
}
