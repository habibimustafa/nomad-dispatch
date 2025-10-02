Nomad Dispatch — GitHub Composite Action

Dispatch a HashiCorp Nomad parameterized job using the Nomad CLI (installed via hashicorp/setup-nomad).

Inputs
- nomad_addr: Nomad HTTP address (e.g., https://nomad.example.com:4646). Required.
- nomad_token: Nomad ACL token (required unless using OIDC authentication).
- oidc_enable: Enable OIDC authentication to get Nomad token from GitHub. Default: false.
- oidc_audience: OIDC audience for token request. Default: nomad.example.com.
- oidc_debug: Enable debug output for OIDC authentication responses. Default: false.
- job_name: Parameterized Nomad job name to dispatch. Required.
- payload: Optional raw string payload (will be base64 encoded).
- meta: Optional metadata as YAML object or JSON string (e.g., key1: val1, key2: val2 or {"key1":"val1"}). Default: {}.
- region: Optional Nomad region.
- namespace: Optional Nomad namespace.
- tls_skip_verify: Skip TLS verification (insecure). Default: false.
- ca_pem: Optional CA PEM content; if provided, written to a temp file and used with curl --cacert.
- live_logs: Show live allocation logs immediately after dispatch (requires task_name). Default: true.
- stream_timeout: Seconds to wait for log activity before closing stream (0 = no timeout). Default: 300.
- auto_close_on_complete: Automatically close log stream when allocation completes. Default: true.
- task_name: Task name to fetch logs for when live_logs=true.
- dry_run: Print request and exit without dispatching. Default: false.
- nomad_version: Nomad CLI version installed by setup-nomad (e.g., latest or 1.8.3). Default: latest.

Outputs
- dispatched_job_id: The dispatched job ID.
- eval_id: The evaluation ID.
- status: Always dispatched.

Usage
Example workflow step dispatching a parameterized job with live log streaming:

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
          live_logs: true
          task_name: "runner"
      - name: Result
        run: |
          echo "Dispatched: ${{ steps.dispatch.outputs.dispatched_job_id }}"
          echo "Eval: ${{ steps.dispatch.outputs.eval_id }}"
          echo "Status: ${{ steps.dispatch.outputs.status }}"
```

**Live Log Streaming:**
Live log streaming is enabled by default. To disable it, set `live_logs: false`:

```yaml
      - name: Dispatch without live logs
        uses: ./
        with:
          nomad_addr: ${{ secrets.NOMAD_ADDR }}
          nomad_token: ${{ secrets.NOMAD_TOKEN }}
          job_name: my-parameterized-job
          payload: "echo hello without logs"
          live_logs: false
```

**Automatic Stream Termination:**
Control when live log streams automatically close:

```yaml
      - name: Dispatch with custom stream termination
        uses: ./
        with:
          nomad_addr: ${{ secrets.NOMAD_ADDR }}
          nomad_token: ${{ secrets.NOMAD_TOKEN }}
          job_name: my-parameterized-job
          payload: "long running job"
          live_logs: true
          stream_timeout: 600          # Close after 10 minutes of inactivity
          auto_close_on_complete: true # Close when allocation completes
          task_name: "runner"
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

OIDC Authentication
Instead of using a pre-configured `nomad_token`, you can enable OIDC authentication to automatically obtain a Nomad token using GitHub's OIDC provider:

```yaml
jobs:
  dispatch:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write  # Required for OIDC
    steps:
      - uses: actions/checkout@v4
      - name: Dispatch with OIDC
        uses: ./
        with:
          nomad_addr: ${{ secrets.NOMAD_ADDR }}
          oidc_enable: true
          oidc_audience: "nomad.example.com"
          job_name: my-parameterized-job
          payload: "authenticated via OIDC"
```

**Requirements for OIDC authentication:**
- The workflow must have `id-token: write` permission
- Nomad must be configured with OIDC authentication method
- The `oidc_audience` should match your Nomad OIDC configuration

**Troubleshooting OIDC authentication:**
- Set `oidc_debug: true` to see the raw Nomad authentication response
- This helps diagnose jq parsing failures and authentication errors

TLS Options
- Set `tls_skip_verify: true` to bypass verification (not recommended for production).
- Provide a CA certificate via `ca_pem: ${{ secrets.NOMAD_CA_PEM }}` to trust a custom CA.

Notes
- The action installs Nomad using `hashicorp/setup-nomad@main` (configurable via `nomad_version`) and uses `nomad job dispatch` for all dispatch operations.
- For live log streaming, set `task_name` to a task within the dispatched allocation. Logs are streamed with `nomad alloc logs -follow`.
- Requires `curl` and `jq` (available on ubuntu-latest runners).
- The parameterized job must be defined in Nomad with appropriate payload/meta handling for the command you intend to run.

License
This action is provided as-is under your repository license.
