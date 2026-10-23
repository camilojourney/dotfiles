import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

export const actions = {
  getQuota: async () => {
    const executable = ["/opt/homebrew/bin/pi", "/usr/local/bin/pi"].find(existsSync) ?? "pi";
    try {
      // Check the existing login without refreshing it, printing credentials,
      // or calling the key-issuing Muse usage endpoint.
      const { stdout } = await execFileAsync(executable, ["auth", "check", "--provider", "meta", "--json", "--no-refresh"], {
        cwd: homedir(),
        timeout: 10_000,
        maxBuffer: 64 * 1024,
        env: { ...process.env, PATH: `/opt/homebrew/bin:/usr/local/bin:${process.env.PATH ?? "/usr/bin:/bin"}` },
      });
      const report = JSON.parse(stdout);
      return { signedIn: report.status === "ready", message: "quota unavailable" };
    } catch {
      return { signedIn: false, message: "Pi Muse status unavailable" };
    }
  },
};
