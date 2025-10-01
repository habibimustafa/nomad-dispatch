Nomad Dispatch — GitHub Composite Action

Dispatch a HashiCorp Nomad parameterized job using the Nomad CLI (installed via hashicorp/setup-nomad).

Inputs
- nomad_addr: Nomad HTTP address (e.g., https://nomad.example.com:4646). Required.
- nomad_token: Nomad ACL token. Required.
- job_name: Parameterized Nomad job name to dispatch. Required.
- payload: Optional raw string payload (will be base64 encoded).
- meta: Optional metadata as YAML object or JSON string (e.g., key1: val1, key2: val2 or {"key1":"val1"}). Default: {}.
- region: Optional Nomad region.
- namespace: Optional Nomad namespace.
- tls_skip_verify: Skip TLS verification (insecure). Default: false.
- ca_pem: Optional CA PEM content; if provided, written to a temp file and used with curl --cacert.
- wait: Wait for allocation(s) to finish. Default: false.
- wait_timeout: Seconds to wait when wait=true. Default: 300.
- print_logs: Print task logs when done (requires task_name). Default: false.
- task_name: Task name to fetch logs for when print_logs=true.
- dry_run: Print request and exit without dispatching. Default: false.
- nomad_version: Nomad CLI version installed by setup-nomad (e.g., latest or 1.8.3). Default: latest.

Outputs
- dispatched_job_id: The dispatched job ID.
- eval_id: The evaluation ID.
- alloc_ids: JSON array of allocation IDs (when wait=true and resolved).
- status: One of dispatched|complete|failed|timeout.

Usage
Example workflow step dispatching a parameterized job and waiting for completion:

```yaml
jobs:
  dispatch:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Dispatch parameterized job
        uses: ./
        with:
          nomad_addr: ${{ secrets.NOMAD_ADDR }}
          nomad_token: ${{ secrets.NOMAD_TOKEN }}
          job_name: my-parameterized-job
          payload: "echo hello from GH Actions"
          meta: |
            trigger: gh-actions
            commit: ${{ github.sha }}
            build_id: ${{ github.run_id }}
          region: ""
          namespace: "default"
          wait: true
          wait_timeout: 600
          print_logs: true
          task_name: "runner"
      - name: Result
        run: |
          echo "Dispatched: ${{ steps.dispatch.outputs.dispatched_job_id }}"
          echo "Eval: ${{ steps.dispatch.outputs.eval_id }}"
          echo "Status: ${{ steps.dispatch.outputs.status }}"
```

Metadata Formats
The `meta` parameter accepts both YAML and JSON formats:

**YAML format (recommended):**
```yaml
meta: |
  environment: production
  version: "1.2.3"
  debug: false
```

**JSON format (backward compatibility):**
```yaml
meta: '{"environment":"production","version":"1.2.3","debug":false}'
```

Dry Run
To validate configuration without dispatching:

```yaml
      - uses: ./
        with:
          nomad_addr: ${{ secrets.NOMAD_ADDR }}
          nomad_token: ${{ secrets.NOMAD_TOKEN }}
          job_name: my-parameterized-job
          payload: "test"
          dry_run: true
```

TLS Options
- Set `tls_skip_verify: true` to bypass verification (not recommended for production).
- Provide a CA certificate via `ca_pem: ${{ secrets.NOMAD_CA_PEM }}` to trust a custom CA.

Notes
- The action installs Nomad using `hashicorp/setup-nomad@main` (configurable via `nomad_version`) and uses `nomad job dispatch` for all dispatch operations.
- For `print_logs: true`, set `task_name` to a task within the dispatched allocation. Logs are fetched with `nomad alloc logs`.
- Requires `curl` and `jq` (available on ubuntu-latest runners).
- The parameterized job must be defined in Nomad with appropriate payload/meta handling for the command you intend to run.

License
This action is provided as-is under your repository license.
