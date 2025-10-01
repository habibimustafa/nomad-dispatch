#!/usr/bin/env bash

# Meta data processing (YAML/JSON conversion) for nomad-dispatch

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Global variables for meta processing
META_JSON=""
META_KV=()

process_meta() {
  # Convert YAML to JSON if needed
  if echo "${META}" | jq -e 'type=="object"' >/dev/null 2>&1; then
    # Input is already valid JSON
    META_JSON="${META}"
  elif [[ "${META}" == "{}" ]]; then
    # Empty default case
    META_JSON="{}"
  else
    # Try to convert YAML to JSON using Python (available in GitHub Actions)
    if command -v python3 >/dev/null 2>&1; then
      META_JSON=$(python3 -c "
import yaml
import json
import sys
try:
    data = yaml.safe_load('''${META}''')
    if data is None:
        data = {}
    elif not isinstance(data, dict):
        print('meta must be an object/dictionary', file=sys.stderr)
        sys.exit(1)
    print(json.dumps(data))
except yaml.YAMLError as e:
    print(f'Invalid YAML in meta input: {e}', file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f'Error processing meta input: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null) || {
        err "meta input must be valid JSON object or YAML object format"
        exit 2
      }
    else
      err "meta input appears to be YAML but python3 is not available for conversion"
      exit 2
    fi
  fi

  if ! echo "${META_JSON}" | jq -e 'type=="object"' >/dev/null 2>&1; then
    err "meta must be a valid JSON/YAML object"
    exit 2
  fi
  readarray -t META_KV < <(echo "${META_JSON}" | jq -r 'to_entries[] | "\(.key)=\(.value|tostring)"' 2>/dev/null || true)
}
