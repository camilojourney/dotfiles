# Native tracing authentication

## Scope

Kind: technical
Capability: native-tracing

Owns: Native shell authentication setup and the local Langfuse header helper.
The separate fresh Langfuse trial remains owned by `agent-platform.md`.

## Requirements

### Private header file

`req~native-tracing.private-header-file~1`

WHEN invoked with `--file`, the helper SHALL atomically refresh an owner-only header file from both existing local Langfuse keys and print only its path.
IF keys are unavailable or incomplete, THEN the helper SHALL fail without printing a path.

Needs: impl, utest

### Shell authentication

`req~native-tracing.shell-authentication~1`

WHEN a managed shell starts, it SHALL remove inherited inline OTLP headers and header-file locations, exporting only `PI_OTEL_EXPORTER_OTLP_HEADERS_FILE` after a successful refresh.
The generated file SHALL authenticate Pi's OTLP HTTP exports without credentials in the shell environment.

Needs: impl, utest, itest

## Helper interface

`scripts/agent-tools/langfuse-otel-headers.sh` reads `LANGFUSE_SECRETS`, defaulting
to `~/.config/secrets/langfuse.env`. It never sources the input as shell code.
With no flag it retains Claude Code's JSON `otelHeadersHelper` response; `--env`
retains percent-encoded OTLP header output. Missing secrets yield `{}` or empty
output respectively for these legacy modes.

`--file` writes `pi-otel/headers` beside the secrets file. The directory is owned
by the current user with mode 0700, and each replacement file has mode 0600.
Symlink directories and destinations are refused. A same-directory temporary
file is renamed only after writing succeeds. Failure leaves any previous file
untouched, but shell startup does not export it. Header contents are a startup
snapshot: rotation requires a new shell and new exporter process.
