import { createHash } from "node:crypto";
import { spawn } from "node:child_process";
import { readFileSync, existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { BabyMenuServerContext } from "@babymenu/contracts";

// Contract: recipes/grok-quota.html. The sole quota source is the exact consumer
// Usage-page operation below - no CLI billing proxy, no cookies, no OAuth, no
// deriving quota from money.
const GRPC_ENDPOINT = "https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig";
const SNAPSHOT_TABLE = "grok_quota_snapshot";
const SCHEMA_VERSION = 2 as const;
const SOURCE = "grok-credits-grpc-web" as const;
const SOURCE_VERSION = 1 as const;
const OPERATION = "grok_api_v2.GrokBuildBilling.GetGrokCreditsConfig" as const;
const PRODUCT_NAMES: Record<number, string> = {
  1: "API",
  2: "Grok Build",
  3: "Grok Plugins",
  4: "Chat",
  5: "Imagine",
  6: "Voice",
};

const REQUEST_TIMEOUT_MS = 15_000;
const RESPONSE_CAP_BYTES = 64 * 1024;
const CLI_TIMEOUT_MS = 20_000;
const CLI_MAX_BUFFER_BYTES = 128 * 1024;

function clampPercent(value: number): number {
  return Math.max(0, Math.min(100, value));
}

// --- normalized types (recipes/grok-quota.html "Normalized Types") ---

type Provenance = {
  percentageField: "config.creditUsagePercent" | `config.productUsage[${number}].usagePercent`;
  resetField?: "config.currentPeriod.end";
  omittedProto3Default?: true;
};

type QuotaWindow = {
  id: "credits" | `product:${string}`;
  label: string;
  percentUsed: number;
  percentRemaining: number;
  resetAt?: string;
  provenance: Provenance;
};

type GrokQuotaSnapshot = {
  schemaVersion: 2;
  source: typeof SOURCE;
  sourceVersion: 1;
  operation: typeof OPERATION;
  accountBinding: string; // storage only, never renderer output
  period: {
    type: "weekly" | "monthly" | "unspecified";
    startAt?: string;
    endAt?: string;
    provenance: "config.currentPeriod";
  };
  windows: QuotaWindow[];
  credits?: { remaining: number; unit: "credits"; sourceField: "config.prepaidBalance.val" };
  refreshedAt: string;
  stale: boolean;
};

type FailureKind =
  | "auth_required"
  | "auth_expired"
  | "auth_scope_ambiguous"
  | "auth_principal_changed"
  | "auth_source_missing"
  | "auth_source_unreadable"
  | "auth_source_malformed"
  | "auth_source_incompatible"
  | "credential_rejected"
  | "cli_not_found"
  | "cli_launch_failed"
  | "connectivity"
  | "rate_limited"
  | "quota_service"
  | "official_quota_source_unavailable"
  | "team_scope_unsupported"
  | "response_too_large"
  | "quota_unreported"
  | "parse_incompatible";

type SourceTried = "local-auth" | "consumer-quota-api" | "grok-cli-refresh" | "cache";

type QuotaFailure = {
  kind: FailureKind;
  message: string;
  sourcesTried: SourceTried[];
  httpStatus?: number;
  grpcStatus?: number;
  retryAt?: string;
  diagnostic?: string;
};

export type GrokQuotaResult =
  | { ok: true; checkedAt: string; data: Omit<GrokQuotaSnapshot, "accountBinding">; warning?: QuotaFailure }
  | { ok: false; checkedAt: string; failure: QuotaFailure };

// --- read-only auth selection ---

type AuthEntry = {
  scope: string;
  key: string;
  expiresAt?: string;
  principalType?: string;
  principalId?: string;
  teamId?: string;
};

type AuthSourceResult =
  | { ok: true; json: Record<string, unknown> }
  | { ok: false; kind: "auth_source_missing" | "auth_source_unreadable" | "auth_source_malformed" };

function resolveAuthPath(): string {
  if (process.env.GROK_AUTH_JSON) return process.env.GROK_AUTH_JSON;
  if (process.env.GROK_AUTH_PATH) return process.env.GROK_AUTH_PATH;
  if (process.env.GROK_HOME) return join(process.env.GROK_HOME, "auth.json");
  return join(homedir(), ".grok", "auth.json");
}

function readAuthSource(): AuthSourceResult {
  const path = resolveAuthPath();
  if (!existsSync(path)) return { ok: false, kind: "auth_source_missing" };
  let raw: string;
  try {
    raw = readFileSync(path, "utf8");
  } catch {
    return { ok: false, kind: "auth_source_unreadable" };
  }
  try {
    return { ok: true, json: JSON.parse(raw) };
  } catch {
    return { ok: false, kind: "auth_source_malformed" };
  }
}

function toEntry(scope: string, raw: unknown): AuthEntry | null {
  if (!raw || typeof raw !== "object") return null;
  const e = raw as Record<string, unknown>;
  const key = e.key;
  if (typeof key !== "string" || key.length === 0) return null;
  return {
    scope,
    key,
    expiresAt: typeof e.expires_at === "string" ? e.expires_at : undefined,
    principalType: typeof e.principal_type === "string" ? e.principal_type : undefined,
    principalId: typeof e.principal_id === "string" ? e.principal_id : undefined,
    teamId: typeof e.team_id === "string" ? e.team_id : undefined,
  };
}

function isExpired(entry: AuthEntry): boolean {
  if (!entry.expiresAt) return false;
  const t = new Date(entry.expiresAt).getTime();
  return Number.isFinite(t) && t <= Date.now();
}

function hasKnownPrincipal(entry: AuthEntry): boolean {
  return typeof entry.principalId === "string" && entry.principalId.length > 0;
}

function accountBinding(entry: AuthEntry): string {
  return createHash("sha256")
    .update(`${entry.principalType ?? ""}:${entry.principalId ?? ""}:${entry.teamId ?? ""}`)
    .digest("hex");
}

type AuthSelection = { ok: true; entry: AuthEntry } | { ok: false; kind: "auth_source_incompatible" | "auth_scope_ambiguous" };

function resolveClass(current: AuthEntry[]): AuthSelection {
  if (current.length > 1) {
    const bindings = new Set(current.map((e) => accountBinding(e)));
    if (bindings.size > 1 || !current.every(hasKnownPrincipal)) {
      return { ok: false, kind: "auth_scope_ambiguous" };
    }
  }
  return { ok: true, entry: current[0] };
}

function selectEntry(json: Record<string, unknown>): AuthSelection {
  const entries = Object.entries(json)
    .map(([scope, raw]) => toEntry(scope, raw))
    .filter((e): e is AuthEntry => e !== null);

  const oidc = entries.filter((e) => e.scope.startsWith("https://auth.x.ai::"));
  const signIn = entries.filter((e) => e.scope.startsWith("https://accounts.x.ai/sign-in"));

  const currentOidc = oidc.filter((e) => !isExpired(e));
  if (currentOidc.length > 0) return resolveClass(currentOidc);

  const currentSignIn = signIn.filter((e) => !isExpired(e));
  if (currentSignIn.length > 0) return resolveClass(currentSignIn);

  // No current supported entry - fall back to an expired one only to drive one
  // conditional official-client refresh.
  const fallback = oidc[0] ?? signIn[0];
  if (fallback) return { ok: true, entry: fallback };

  return { ok: false, kind: "auth_source_incompatible" };
}

// --- conditional official-client refresh ---

function searchPath(): string | null {
  for (const dir of (process.env.PATH ?? "").split(":")) {
    if (!dir) continue;
    const candidate = join(dir, "grok");
    if (existsSync(candidate)) return candidate;
  }
  return null;
}

function discoverGrokCli(): string | null {
  if (process.env.GROK_CLI_PATH && existsSync(process.env.GROK_CLI_PATH)) return process.env.GROK_CLI_PATH;
  if (process.env.GROK_HOME) {
    const home = join(process.env.GROK_HOME, "bin", "grok");
    if (existsSync(home)) return home;
  }
  const onPath = searchPath();
  if (onPath) return onPath;
  const homeLocal = join(homedir(), ".grok", "bin", "grok");
  if (existsSync(homeLocal)) return homeLocal;
  for (const candidate of ["/opt/homebrew/bin/grok", "/usr/local/bin/grok"]) {
    if (existsSync(candidate)) return candidate;
  }
  return null;
}

type CliRefreshOutcome = { ok: true } | { ok: false; kind: "cli_launch_failed" };

function runGrokRefresh(cliPath: string): Promise<CliRefreshOutcome> {
  // Success is never inferred from CLI exit status or output - only from
  // rereading auth.json afterward, so the exit/error callbacks below only
  // resolve whether the process ran, not whether sign-in succeeded.
  return new Promise((resolve) => {
    let settled = false;
    const finish = (outcome: CliRefreshOutcome) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(outcome);
    };

    let child;
    try {
      child = spawn(cliPath, ["models"], {
        stdio: ["ignore", "pipe", "pipe"],
        detached: process.platform !== "win32",
        shell: false,
        env: process.env,
        windowsHide: true,
      });
    } catch {
      resolve({ ok: false, kind: "cli_launch_failed" });
      return;
    }

    let stdoutBytes = 0;
    let stderrBytes = 0;
    child.stdout?.on("data", (chunk: Buffer) => {
      stdoutBytes += chunk.length;
      if (stdoutBytes > CLI_MAX_BUFFER_BYTES) child.stdout?.pause();
    });
    child.stderr?.on("data", (chunk: Buffer) => {
      stderrBytes += chunk.length;
      if (stderrBytes > CLI_MAX_BUFFER_BYTES) child.stderr?.pause();
    });

    child.once("error", () => finish({ ok: false, kind: "cli_launch_failed" }));
    child.once("exit", () => finish({ ok: true }));

    const timer = setTimeout(() => {
      const pid = child.pid;
      if (pid === undefined) {
        finish({ ok: true });
        return;
      }
      const target = process.platform === "win32" ? pid : -pid;
      try {
        process.kill(target, "SIGTERM");
      } catch (err) {
        if ((err as NodeJS.ErrnoException).code !== "ESRCH") {
          finish({ ok: false, kind: "cli_launch_failed" });
          return;
        }
      }
      setTimeout(() => {
        try {
          process.kill(target, "SIGKILL");
        } catch (err) {
          // ESRCH: already gone. EPERM: best-effort suppression - we do not walk
          // the process table to confirm the group is fully dead.
          const code = (err as NodeJS.ErrnoException).code;
          if (code !== "ESRCH" && code !== "EPERM") {
            finish({ ok: false, kind: "cli_launch_failed" });
            return;
          }
        }
        finish({ ok: true });
      }, 1_000);
    }, CLI_TIMEOUT_MS);
  });
}

// --- gRPC-web request ---

type HttpOutcome =
  | { kind: "ok"; httpStatus: number; grpcStatus?: number; grpcMessage?: string; body?: Buffer }
  | { kind: "timeout" }
  | { kind: "network" }
  | { kind: "too_large" };

type Frame = { flag: number; payload: Buffer };

// Lenient framing used only to read a best-effort trailer grpc-status/message;
// the authoritative data-frame validation is parseFramesStrict below.
function parseFrames(buf: Buffer): Frame[] {
  const frames: Frame[] = [];
  let pos = 0;
  while (pos + 5 <= buf.length) {
    const flag = buf.readUInt8(pos);
    const len = buf.readUInt32BE(pos + 1);
    const start = pos + 5;
    const end = start + len;
    if (end > buf.length) break;
    frames.push({ flag, payload: buf.subarray(start, end) });
    pos = end;
  }
  return frames;
}

function readTrailer(buf: Buffer): { grpcStatus?: number; grpcMessage?: string } {
  const trailerFrame = parseFrames(buf).find((f) => (f.flag & 0x80) !== 0);
  if (!trailerFrame) return {};
  const text = trailerFrame.payload.toString("utf8");
  const statusMatch = text.match(/grpc-status:\s*(\d+)/i);
  const messageMatch = text.match(/grpc-message:\s*([^\r\n]+)/i);
  return {
    grpcStatus: statusMatch ? Number(statusMatch[1]) : undefined,
    grpcMessage: messageMatch ? decodeURIComponent(messageMatch[1].trim()) : undefined,
  };
}

async function callGetCreditsConfig(bearer: string): Promise<HttpOutcome> {
  const controller = new AbortController();
  let timedOut = false;
  const timeout = setTimeout(() => {
    timedOut = true;
    controller.abort();
  }, REQUEST_TIMEOUT_MS);
  try {
    const res = await fetch(GRPC_ENDPOINT, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${bearer}`,
        Accept: "*/*",
        "Content-Type": "application/grpc-web+proto",
        Origin: "https://grok.com",
        Referer: "https://grok.com/?_s=usage",
        "x-grpc-web": "1",
        "x-user-agent": "connect-es/2.1.1",
      },
      body: Buffer.from([0, 0, 0, 0, 0]),
      signal: controller.signal,
    });
    const buf = Buffer.from(await res.arrayBuffer());
    if (buf.length > RESPONSE_CAP_BYTES) return { kind: "too_large" };

    const headerGrpcStatus = res.headers.get("grpc-status");
    const headerGrpcMessage = res.headers.get("grpc-message");
    const trailer = readTrailer(buf);

    return {
      kind: "ok",
      httpStatus: res.status,
      grpcStatus: trailer.grpcStatus ?? (headerGrpcStatus ? Number(headerGrpcStatus) : undefined),
      grpcMessage: trailer.grpcMessage ?? (headerGrpcMessage ? decodeURIComponent(headerGrpcMessage) : undefined),
      body: buf,
    };
  } catch {
    return timedOut ? { kind: "timeout" } : { kind: "network" };
  } finally {
    clearTimeout(timeout);
  }
}

function isRetryableTransport(outcome: HttpOutcome): boolean {
  if (outcome.kind === "timeout") return true;
  if (outcome.kind !== "ok") return false;
  if ([408, 502, 503, 504].includes(outcome.httpStatus)) return true;
  // gRPC 1 = CANCELLED, gRPC 4 = DEADLINE_EXCEEDED.
  return outcome.grpcStatus === 1 || outcome.grpcStatus === 4;
}

async function requestCreditsConfig(bearer: string): Promise<HttpOutcome> {
  const first = await callGetCreditsConfig(bearer);
  if (isRetryableTransport(first)) return callGetCreditsConfig(bearer);
  return first;
}

function isCredentialRefreshTrigger(outcome: HttpOutcome): boolean {
  if (outcome.kind !== "ok") return false;
  if (outcome.httpStatus === 401 || outcome.grpcStatus === 16) return true;
  return outcome.grpcStatus === 7 && !!outcome.grpcMessage && /bad-credentials|unauthenticated/i.test(outcome.grpcMessage);
}

function classify(outcome: HttpOutcome): { kind: FailureKind | "ok" } {
  if (outcome.kind === "too_large") return { kind: "response_too_large" };
  if (outcome.kind === "timeout" || outcome.kind === "network") return { kind: "connectivity" };
  const { httpStatus, grpcStatus, grpcMessage } = outcome;
  // HTTP 403 remains a rejected credential/permission outcome but never triggers refresh.
  if (httpStatus === 401 || httpStatus === 403 || grpcStatus === 16) return { kind: "credential_rejected" };
  if (grpcStatus === 7 && grpcMessage && /bad-credentials|unauthenticated/i.test(grpcMessage)) return { kind: "credential_rejected" };
  if (grpcStatus === 9 && grpcMessage && /team/i.test(grpcMessage)) return { kind: "team_scope_unsupported" };
  if (httpStatus === 429 || grpcStatus === 8) return { kind: "rate_limited" };
  if ([408, 502, 503, 504].includes(httpStatus) || httpStatus >= 500) return { kind: "quota_service" };
  if (httpStatus === 200) return { kind: "ok" };
  return { kind: "official_quota_source_unavailable" };
}

// --- typed protobuf decoder ---

type ProtoField = { fieldNum: number; wireType: number; value?: bigint; float?: number; bytes?: Buffer };

function readVarint(buf: Buffer, pos: number): [bigint, number] {
  let result = 0n;
  let shift = 0n;
  let p = pos;
  while (true) {
    if (p >= buf.length) throw new Error("varint out of bounds");
    const b = buf[p++];
    result |= BigInt(b & 0x7f) << shift;
    if ((b & 0x80) === 0) break;
    shift += 7n;
    if (shift > 63n) throw new Error("varint too long");
  }
  return [result, p];
}

function decodeProto(buf: Buffer): ProtoField[] {
  const out: ProtoField[] = [];
  let pos = 0;
  while (pos < buf.length) {
    let tag: bigint;
    [tag, pos] = readVarint(buf, pos);
    const fieldNum = Number(tag >> 3n);
    const wireType = Number(tag & 7n);
    if (wireType === 0) {
      let v: bigint;
      [v, pos] = readVarint(buf, pos);
      out.push({ fieldNum, wireType, value: v });
    } else if (wireType === 5) {
      if (pos + 4 > buf.length) throw new Error("float32 out of bounds");
      const float = buf.readFloatLE(pos);
      pos += 4;
      out.push({ fieldNum, wireType, float });
    } else if (wireType === 1) {
      if (pos + 8 > buf.length) throw new Error("fixed64 out of bounds");
      pos += 8;
      out.push({ fieldNum, wireType });
    } else if (wireType === 2) {
      let len: bigint;
      [len, pos] = readVarint(buf, pos);
      const end = pos + Number(len);
      if (Number(len) < 0 || end > buf.length) throw new Error("length-delimited out of bounds");
      const bytes = buf.subarray(pos, end);
      pos = end;
      out.push({ fieldNum, wireType, bytes });
    } else {
      throw new Error("unsupported wire type");
    }
  }
  return out;
}

function decodeTimestamp(bytes: Buffer): string | undefined {
  let seconds = 0n;
  let nanos = 0n;
  for (const f of decodeProto(bytes)) {
    if (f.fieldNum === 1 && f.value !== undefined) seconds = f.value;
    if (f.fieldNum === 2 && f.value !== undefined) nanos = f.value;
  }
  const ms = Number(seconds) * 1000 + Number(nanos) / 1e6;
  if (!Number.isFinite(ms)) return undefined;
  return new Date(ms).toISOString();
}

// Observed live evidence: config.currentPeriod field 1 = 2 for a verified 7-day
// (weekly) start/end span. Duration is kept as a fallback for an unrecognized
// enum value rather than a primary guess.
function periodTypeFromField(raw: number | undefined, startAt?: string, endAt?: string): "weekly" | "monthly" | "unspecified" {
  if (raw === 2) return "weekly";
  if (raw === 1) return "monthly";
  if (startAt && endAt) {
    const days = (new Date(endAt).getTime() - new Date(startAt).getTime()) / 86_400_000;
    if (days >= 6 && days <= 8) return "weekly";
    if (days >= 27 && days <= 32) return "monthly";
  }
  return "unspecified";
}

type DecodedConfig =
  | { kind: "ok"; period: GrokQuotaSnapshot["period"]; windows: QuotaWindow[]; credits?: GrokQuotaSnapshot["credits"] }
  | { kind: "unreported" }
  | { kind: "malformed" };

function decodeConfig(bytes: Buffer): DecodedConfig {
  let fields: ProtoField[];
  try {
    fields = decodeProto(bytes);
  } catch {
    return { kind: "malformed" };
  }

  let creditFieldPresent = false;
  let creditUsagePercent: number | undefined;
  const products: Array<{ id: number; percentUsed?: number }> = [];
  let periodTypeRaw: number | undefined;
  let periodStart: string | undefined;
  let periodEnd: string | undefined;
  let prepaidCents: bigint | undefined;

  try {
    for (const f of fields) {
      if (f.fieldNum === 1 && f.wireType === 5) {
        creditFieldPresent = true;
        creditUsagePercent = f.float;
      } else if (f.fieldNum === 7 && f.bytes) {
        const sub = decodeProto(f.bytes);
        let productId: number | undefined;
        let usedPercentage: number | undefined;
        for (const s of sub) {
          if (s.fieldNum === 1 && s.value !== undefined) productId = Number(s.value);
          if (s.fieldNum === 2 && s.wireType === 5) usedPercentage = s.float;
        }
        if (productId !== undefined) products.push({ id: productId, percentUsed: usedPercentage });
      } else if (f.fieldNum === 8 && f.bytes) {
        const sub = decodeProto(f.bytes);
        for (const s of sub) {
          if (s.fieldNum === 1 && s.value !== undefined) periodTypeRaw = Number(s.value);
          if (s.fieldNum === 2 && s.bytes) periodStart = decodeTimestamp(s.bytes);
          if (s.fieldNum === 3 && s.bytes) periodEnd = decodeTimestamp(s.bytes);
        }
      } else if (f.fieldNum === 12 && f.bytes) {
        let cents = 0n;
        for (const s of decodeProto(f.bytes)) {
          if (s.fieldNum === 1 && s.value !== undefined) cents = s.value;
        }
        prepaidCents = cents;
      }
    }
  } catch {
    return { kind: "malformed" };
  }

  const periodType = periodTypeFromField(periodTypeRaw, periodStart, periodEnd);
  const hasValidPeriod = periodType !== "unspecified";

  if (!creditFieldPresent && products.length === 0 && !hasValidPeriod) {
    return { kind: "unreported" };
  }

  const windows: QuotaWindow[] = [];
  if (creditFieldPresent || hasValidPeriod) {
    const percentUsed = clampPercent(creditUsagePercent ?? 0);
    windows.push({
      id: "credits",
      label: "credits",
      percentUsed,
      percentRemaining: 100 - percentUsed,
      resetAt: periodEnd,
      provenance: {
        percentageField: "config.creditUsagePercent",
        resetField: periodEnd ? "config.currentPeriod.end" : undefined,
        omittedProto3Default: creditFieldPresent ? undefined : true,
      },
    });
  }
  products.forEach((p, index) => {
    const percentUsed = clampPercent(p.percentUsed ?? 0);
    const name = PRODUCT_NAMES[p.id] ?? `product ${p.id}`;
    windows.push({
      id: `product:${name}`,
      label: name,
      percentUsed,
      percentRemaining: 100 - percentUsed,
      resetAt: periodEnd,
      provenance: {
        percentageField: `config.productUsage[${index}].usagePercent`,
        resetField: periodEnd ? "config.currentPeriod.end" : undefined,
        omittedProto3Default: p.percentUsed === undefined ? true : undefined,
      },
    });
  });

  return {
    kind: "ok",
    period: { type: periodType, startAt: periodStart, endAt: periodEnd, provenance: "config.currentPeriod" },
    windows,
    credits: prepaidCents !== undefined ? { remaining: Number(prepaidCents) / 100, unit: "credits", sourceField: "config.prepaidBalance.val" } : undefined,
  };
}

function parseFramesStrict(buf: Buffer): { ok: true; frames: Frame[] } | { ok: false } {
  const frames: Frame[] = [];
  let pos = 0;
  while (pos < buf.length) {
    if (pos + 5 > buf.length) return { ok: false };
    const flag = buf.readUInt8(pos);
    const len = buf.readUInt32BE(pos + 1);
    const start = pos + 5;
    const end = start + len;
    if (end > buf.length) return { ok: false };
    frames.push({ flag, payload: buf.subarray(start, end) });
    pos = end;
  }
  return { ok: true, frames };
}

function decodeResponseBody(buf: Buffer): DecodedConfig {
  const parsed = parseFramesStrict(buf);
  if (!parsed.ok) return { kind: "malformed" };

  const dataFrames = parsed.frames.filter((f) => (f.flag & 0x80) === 0);
  if (dataFrames.length !== 1) return { kind: "malformed" };
  const [dataFrame] = dataFrames;
  if ((dataFrame.flag & 0x01) !== 0) return { kind: "malformed" }; // compressed frame - unsupported

  let top: ProtoField[];
  try {
    top = decodeProto(dataFrame.payload);
  } catch {
    return { kind: "malformed" };
  }
  const configField = top.find((f) => f.fieldNum === 1 && f.bytes);
  if (!configField?.bytes) return { kind: "malformed" };
  return decodeConfig(configField.bytes);
}

// --- schema version 2 cache trust boundary ---

function ensureTable(context: BabyMenuServerContext) {
  context.db.exec(`CREATE TABLE IF NOT EXISTS ${SNAPSHOT_TABLE} (id INTEGER PRIMARY KEY CHECK (id = 1), binding TEXT NOT NULL, json TEXT NOT NULL)`);
}

function isTrustedSnapshot(value: unknown): value is GrokQuotaSnapshot {
  if (!value || typeof value !== "object") return false;
  const v = value as Record<string, unknown>;
  return (
    v.schemaVersion === SCHEMA_VERSION &&
    v.source === SOURCE &&
    v.sourceVersion === SOURCE_VERSION &&
    v.operation === OPERATION &&
    typeof v.accountBinding === "string" &&
    Array.isArray(v.windows) &&
    (v.windows as unknown[]).every((w) => w && typeof w === "object" && "provenance" in (w as Record<string, unknown>))
  );
}

function getCachedSnapshot(context: BabyMenuServerContext, binding: string): GrokQuotaSnapshot | null {
  ensureTable(context);
  const row = context.db.get<{ binding: string; json: string }>(`SELECT binding, json FROM ${SNAPSHOT_TABLE} WHERE id = 1`);
  if (!row) return null;
  let parsed: unknown;
  try {
    parsed = JSON.parse(row.json);
  } catch {
    context.db.run(`DELETE FROM ${SNAPSHOT_TABLE} WHERE id = 1`);
    return null;
  }
  if (!isTrustedSnapshot(parsed)) {
    context.db.run(`DELETE FROM ${SNAPSHOT_TABLE} WHERE id = 1`);
    return null;
  }
  if (parsed.accountBinding !== binding) return null;
  return parsed;
}

function saveSnapshot(context: BabyMenuServerContext, binding: string, snapshot: GrokQuotaSnapshot) {
  ensureTable(context);
  context.db.run(
    `INSERT INTO ${SNAPSHOT_TABLE} (id, binding, json) VALUES (1, ?, ?) ON CONFLICT(id) DO UPDATE SET binding = excluded.binding, json = excluded.json`,
    [binding, JSON.stringify(snapshot)],
  );
}

function withoutBinding(snapshot: GrokQuotaSnapshot): Omit<GrokQuotaSnapshot, "accountBinding"> {
  const { accountBinding: _drop, ...rest } = snapshot;
  return rest;
}

// Only eligible transport/service failures (and a failed conditional refresh)
// may fall back to a same-principal cached snapshot, rendered stale.
function withCacheFallback(
  context: BabyMenuServerContext,
  binding: string,
  kind: FailureKind,
  message: string,
  sourceTried: SourceTried[],
  checkedAt: string,
): GrokQuotaResult {
  const cached = getCachedSnapshot(context, binding);
  if (cached) {
    sourceTried.push("cache");
    return {
      ok: true,
      checkedAt,
      data: { ...withoutBinding(cached), stale: true },
      warning: { kind, message, sourcesTried: sourceTried },
    };
  }
  return { ok: false, checkedAt, failure: { kind, message, sourcesTried: sourceTried } };
}

// --- acquisition ---

async function acquireQuota(context: BabyMenuServerContext): Promise<GrokQuotaResult> {
  const checkedAt = new Date().toISOString();
  const sourceTried: SourceTried[] = ["local-auth"];

  const authSource = readAuthSource();
  if (!authSource.ok) {
    return { ok: false, checkedAt, failure: { kind: authSource.kind, message: "Grok sign-in required", sourcesTried: sourceTried } };
  }

  const selection = selectEntry(authSource.json);
  if (!selection.ok) {
    const message = selection.kind === "auth_scope_ambiguous" ? "Multiple Grok sign-ins found; refresh baby menu" : "Grok sign-in required";
    return { ok: false, checkedAt, failure: { kind: selection.kind, message, sourcesTried: sourceTried } };
  }

  let entry = selection.entry;
  const bindingBefore = accountBinding(entry);
  let refreshed = false;

  if (isExpired(entry)) {
    const cliPath = discoverGrokCli();
    if (!cliPath) {
      return withCacheFallback(context, bindingBefore, "cli_not_found", "Grok sign-in required", sourceTried, checkedAt);
    }
    sourceTried.push("grok-cli-refresh");
    const refreshOutcome = await runGrokRefresh(cliPath);
    if (!refreshOutcome.ok) {
      return withCacheFallback(context, bindingBefore, "cli_launch_failed", "Grok sign-in required", sourceTried, checkedAt);
    }
    refreshed = true;

    const rereadSource = readAuthSource();
    const rereadSelection = rereadSource.ok ? selectEntry(rereadSource.json) : null;
    if (!rereadSelection || !rereadSelection.ok) {
      return { ok: false, checkedAt, failure: { kind: "auth_expired", message: "Grok sign-in required", sourcesTried: sourceTried } };
    }
    if (isExpired(rereadSelection.entry)) {
      return { ok: false, checkedAt, failure: { kind: "auth_expired", message: "Grok sign-in required", sourcesTried: sourceTried } };
    }
    if (accountBinding(rereadSelection.entry) !== bindingBefore) {
      return { ok: false, checkedAt, failure: { kind: "auth_principal_changed", message: "Grok account changed locally; refresh baby menu", sourcesTried: sourceTried } };
    }
    entry = rereadSelection.entry;
  }

  const binding = accountBinding(entry);
  sourceTried.push("consumer-quota-api");
  let outcome = await requestCreditsConfig(entry.key);

  if (isCredentialRefreshTrigger(outcome) && !refreshed) {
    const cliPath = discoverGrokCli();
    if (cliPath) {
      sourceTried.push("grok-cli-refresh");
      const refreshOutcome = await runGrokRefresh(cliPath);
      if (refreshOutcome.ok) {
        const rereadSource = readAuthSource();
        const rereadSelection = rereadSource.ok ? selectEntry(rereadSource.json) : null;
        if (rereadSelection && rereadSelection.ok && !isExpired(rereadSelection.entry) && accountBinding(rereadSelection.entry) === binding) {
          entry = rereadSelection.entry;
          outcome = await requestCreditsConfig(entry.key);
        }
      }
    }
  }

  const classification = classify(outcome);
  const httpStatus = outcome.kind === "ok" ? outcome.httpStatus : undefined;
  const grpcStatus = outcome.kind === "ok" ? outcome.grpcStatus : undefined;

  if (classification.kind === "credential_rejected") {
    return { ok: false, checkedAt, failure: { kind: "credential_rejected", message: "Grok sign-in required", sourcesTried: sourceTried, httpStatus, grpcStatus } };
  }
  if (classification.kind === "team_scope_unsupported") {
    return { ok: false, checkedAt, failure: { kind: "team_scope_unsupported", message: "Grok team scope not supported", sourcesTried: sourceTried, grpcStatus } };
  }
  if (classification.kind === "rate_limited") {
    return { ok: false, checkedAt, failure: { kind: "rate_limited", message: "Grok quota check rate limited", sourcesTried: sourceTried, httpStatus, grpcStatus } };
  }
  if (classification.kind === "response_too_large") {
    return { ok: false, checkedAt, failure: { kind: "response_too_large", message: "Grok quota response too large", sourcesTried: sourceTried } };
  }
  if (classification.kind === "connectivity" || classification.kind === "quota_service") {
    return withCacheFallback(context, binding, classification.kind, "Grok quota unavailable", sourceTried, checkedAt);
  }
  if (classification.kind === "official_quota_source_unavailable") {
    return { ok: false, checkedAt, failure: { kind: "official_quota_source_unavailable", message: "Grok quota source unavailable", sourcesTried: sourceTried, httpStatus } };
  }

  if (outcome.kind !== "ok" || !outcome.body) {
    return { ok: false, checkedAt, failure: { kind: "parse_incompatible", message: "Grok quota response malformed", sourcesTried: sourceTried } };
  }

  const decoded = decodeResponseBody(outcome.body);
  if (decoded.kind === "malformed") {
    return { ok: false, checkedAt, failure: { kind: "parse_incompatible", message: "Grok quota response could not be parsed", sourcesTried: sourceTried } };
  }
  if (decoded.kind === "unreported") {
    return { ok: false, checkedAt, failure: { kind: "quota_unreported", message: "Grok did not report quota for this account", sourcesTried: sourceTried } };
  }

  const snapshot: GrokQuotaSnapshot = {
    schemaVersion: SCHEMA_VERSION,
    source: SOURCE,
    sourceVersion: SOURCE_VERSION,
    operation: OPERATION,
    accountBinding: binding,
    period: decoded.period,
    windows: decoded.windows,
    credits: decoded.credits,
    refreshedAt: checkedAt,
    stale: false,
  };

  saveSnapshot(context, binding, snapshot);
  return { ok: true, checkedAt, data: withoutBinding(snapshot) };
}

let inFlight: Promise<GrokQuotaResult> | null = null;

export const actions = {
  getQuota: async (_input: unknown, context: BabyMenuServerContext): Promise<GrokQuotaResult> => {
    if (inFlight) return inFlight;
    inFlight = acquireQuota(context).finally(() => {
      inFlight = null;
    });
    return inFlight;
  },
};
