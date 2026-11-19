// Use the tested extension's locked loader and real OTLP trace runtime.
import { pathToFileURL } from "node:url";
import { join } from "node:path";
const source = process.argv[2];
const { createJiti } = await import(pathToFileURL(join(source, "node_modules/jiti/lib/jiti.mjs")));
const jiti = createJiti(import.meta.url, { fsCache: false });
const { getConfig } = await jiti.import(join(source, "src/config.ts"));
const { createTraceRuntime } = await jiti.import(join(source, "src/trace/provider.ts"));
if (process.env.PI_OTEL_EXPORTER_OTLP_HEADERS !== undefined ||
    process.env.OTEL_EXPORTER_OTLP_HEADERS !== undefined) throw new Error("Inline headers survived");
const errors = [];
const runtime = createTraceRuntime(getConfig(), () => errors.push(true));
runtime.tracer.startSpan("synthetic-private-file-export").end();
await runtime.shutdown();
if (errors.length) throw new Error("OTLP export failed");
