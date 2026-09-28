import { spawn } from "node:child_process";

const CAPTURE_TIMEOUT_MS = 40_000;
const MAX_OUTPUT_BYTES = 256 * 1024;

type QuotaBucket = {
  id: "gemini" | "claude-gpt";
  label: string;
  percentUsed: number;
  percentRemaining: number;
  windowLabel: "weekly";
  refreshesIn?: string;
};

type CaptureResult =
  | { ok: true; output: string }
  | { ok: false; error: string };

// Antigravity's /usage screen requires a real terminal. Python's standard PTY
// module gives the CLI one without introducing a package dependency.
const PTY_CAPTURE_SCRIPT = String.raw`
import base64, fcntl, os, pty, select, signal, struct, subprocess, sys, termios, time

master, slave = pty.openpty()
for fd in (master, slave):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 220, 0, 0))

env = os.environ.copy()
if env.get("TERM", "").lower() in ("", "dumb", "unknown"):
    env["TERM"] = "xterm-256color"

proc = subprocess.Popen(
    ["agy"], stdin=slave, stdout=slave, stderr=slave,
    start_new_session=True, env=env,
)
os.close(slave)
buffer = bytearray()
sent_usage = False
trusted = False
deadline = time.time() + 35

try:
    while time.time() < deadline:
        ready, _, _ = select.select([master], [], [], 0.25)
        if ready:
            try:
                chunk = os.read(master, 65536)
            except OSError:
                break
            if not chunk:
                break
            buffer.extend(chunk)
            text = buffer.decode("utf-8", errors="ignore")
            if not trusted and "Do you trust the contents of this project?" in text:
                os.write(master, b"\r")
                trusted = True
            if not sent_usage and "? for shortcuts" in text:
                os.write(master, b"/usage\r")
                sent_usage = True
            if "Models & Quota" in text and text.count("Weekly Limit") >= 2:
                time.sleep(1)
                ready, _, _ = select.select([master], [], [], 0.5)
                if ready:
                    try:
                        buffer.extend(os.read(master, 65536))
                    except OSError:
                        pass
                break
finally:
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except Exception:
        pass
    try:
        proc.wait(timeout=2)
    except Exception:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except Exception:
            pass

sys.stdout.write(base64.b64encode(bytes(buffer)).decode("ascii"))
`;

function captureUsageScreen(): Promise<CaptureResult> {
  return new Promise((resolve) => {
    const child = spawn("python3", ["-c", PTY_CAPTURE_SCRIPT], {
      stdio: ["ignore", "pipe", "pipe"],
    });
    const chunks: Buffer[] = [];
    let byteCount = 0;
    let settled = false;

    const finish = (result: CaptureResult) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      resolve(result);
    };

    child.stdout.on("data", (chunk: Buffer) => {
      byteCount += chunk.length;
      if (byteCount > MAX_OUTPUT_BYTES) {
        child.kill("SIGKILL");
        finish({ ok: false, error: "Antigravity quota response was too large" });
        return;
      }
      chunks.push(chunk);
    });
    child.once("error", (error: Error & { code?: string }) => {
      finish({
        ok: false,
        error: error.code === "ENOENT" ? "Python is unavailable for the Antigravity terminal" : "Antigravity quota capture could not start",
      });
    });
    child.once("exit", (code) => {
      if (settled) return;
      if (code !== 0) {
        finish({ ok: false, error: "Antigravity quota capture failed" });
        return;
      }
      try {
        const encoded = Buffer.concat(chunks).toString("utf8").trim();
        finish({ ok: true, output: Buffer.from(encoded, "base64").toString("utf8") });
      } catch {
        finish({ ok: false, error: "Antigravity quota response could not be decoded" });
      }
    });

    const timeout = setTimeout(() => {
      child.kill("SIGKILL");
      finish({ ok: false, error: "Antigravity quota capture timed out" });
    }, CAPTURE_TIMEOUT_MS);
  });
}

function cleanTerminal(text: string): string {
  return text
    .replace(/\x1b\][^\x07]*(?:\x07|\x1b\\)/g, "")
    .replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "")
    .replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, "");
}

function parseQuotaScreen(raw: string): { plan?: string; buckets: QuotaBucket[] } {
  const text = cleanTerminal(raw);
  const planMatch = text.match(/\((Google AI [^)]+)\)/);
  const groupPattern =
    /(GEMINI MODELS|CLAUDE AND GPT MODELS)[\s\S]*?Weekly Limit[\s\S]*?(\d+(?:\.\d+)?)%[\s\S]*?Refreshes in ([^\n]+)/g;
  const buckets: QuotaBucket[] = [];
  let match: RegExpExecArray | null;

  while ((match = groupPattern.exec(text)) !== null) {
    const percentRemaining = Math.max(0, Math.min(100, Number(match[2])));
    const gemini = match[1] === "GEMINI MODELS";
    buckets.push({
      id: gemini ? "gemini" : "claude-gpt",
      label: gemini ? "Gemini models" : "Claude + GPT models",
      percentUsed: 100 - percentRemaining,
      percentRemaining,
      windowLabel: "weekly",
      refreshesIn: match[3].trim(),
    });
  }

  return { plan: planMatch?.[1], buckets };
}

export const actions = {
  getQuota: async () => {
    const capture = await captureUsageScreen();
    if (!capture.ok) return capture;

    const parsed = parseQuotaScreen(capture.output);
    if (parsed.buckets.length === 0) {
      return { ok: false as const, error: "Antigravity /usage did not report model quota" };
    }

    return {
      ok: true as const,
      data: {
        source: "agy /usage" as const,
        plan: parsed.plan,
        buckets: parsed.buckets,
        checkedAt: new Date().toISOString(),
      },
    };
  },
};
