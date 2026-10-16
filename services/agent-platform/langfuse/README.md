# Fresh tracing configuration

These are native Docker Compose and Lima definitions, not a new runtime framework.
See the [runbook](../../../docs/AGENT-PLATFORM-LANGFUSE.md) before starting them.

## Declarative implementation map

The current specification checker's tag importer excludes JSON and XML. This
adjacent map supplies trace entries for those files; embedded tags remain in the
artifacts. The map is not behavioral proof: native vendor validation, static tests
and private end-to-end evidence are separate checks.

<!-- [impl->req~agent-platform.langfuse-isolation~1] -->
[compose.json](compose.json) defines private ports, immutable images and resource
limits; [common.json](common.json) owns shared restart/logging/connection settings.
[clickhouse-memory.xml](clickhouse-memory.xml) bounds server memory and file logs.

<!-- [impl->req~agent-platform.langfuse-credentials~1] -->
The Redis command in [compose.json](compose.json) reads its environment internally
and writes a private configuration before the service-user entrypoint. Other
services consume their private environment, not expanded credential arguments.

<!-- [impl->req~agent-platform.langfuse-query-pool~1] -->
[clickhouse-memory.xml](clickhouse-memory.xml) deliberately omits an artificial
global-thread ceiling while retaining memory and concurrent-query admission limits.

[lima.yaml](lima.yaml) owns the VM boundary and guest package pins.
[runtime.json](runtime.json) owns the host Lima release/hash.
