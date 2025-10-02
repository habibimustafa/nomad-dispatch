#!/usr/bin/env bash

# OIDC authentication functionality for nomad-dispatch

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

get_oidc_token() {
  if [[ "${OIDC_ENABLE}" != "true" ]]; then
    return 0
  fi

  # Check if we're running in GitHub Actions
  if [[ -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" || -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]]; then
    err "OIDC authentication requires GitHub Actions environment with id-token: write permission"
    exit 2
  fi

  note "Getting OIDC token from GitHub"

  # Get GitHub OIDC token
  local github_token
  github_token=$(curl -s -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
    "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${OIDC_AUDIENCE}" | jq -r '.value')

  if [[ -z "${github_token}" || "${github_token}" == "null" ]]; then
    err "Failed to get GitHub OIDC token"
    exit 2
  fi

  # Exchange GitHub OIDC token for Nomad token
  note "Authenticating with Nomad using OIDC token"

  local curl_args=()
  curl_args+=("-s")
  curl_args+=("-X" "POST")
  curl_args+=("-H" "Content-Type: application/json")
  curl_args+=("-d" "{\"AuthMethod\":\"github\",\"JWT\":\"${github_token}\"}")

  # Add TLS options
  if [[ "${TLS_SKIP_VERIFY}" == "true" ]]; then
    curl_args+=("-k")
  fi
  if [[ -n "${CACERT_FILE}" ]]; then
    curl_args+=("--cacert" "${CACERT_FILE}")
  fi
  if [[ -n "${CLIENT_CERT_FILE}" && -n "${CLIENT_KEY_FILE}" ]]; then
    curl_args+=("--cert" "${CLIENT_CERT_FILE}")
    curl_args+=("--key" "${CLIENT_KEY_FILE}")
  fi

  local nomad_auth_response
  nomad_auth_response=$(curl "${curl_args[@]}" "${NOMAD_ADDR}/v1/acl/login")

  if [[ $? -ne 0 ]]; then
    err "Failed to authenticate with Nomad using OIDC"
    exit 2
  fi

  # Debug output for the raw response
  if [[ "${OIDC_DEBUG}" == "true" ]]; then
    note "OIDC Debug: Raw Nomad auth response:"
    echo "${nomad_auth_response}" >&2
  fi

  # Extract token from response
  local nomad_token
  nomad_token=$(echo "${nomad_auth_response}" | jq -r '.SecretID // empty')

  if [[ -z "${nomad_token}" ]]; then
    err "Failed to extract Nomad token from OIDC authentication response"
    err "Response: ${nomad_auth_response}"
    exit 2
  fi

  # Set the token for use by other scripts
  export NOMAD_TOKEN="${nomad_token}"
  note "Successfully authenticated with Nomad via OIDC"
}
