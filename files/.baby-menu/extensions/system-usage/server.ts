import { cpus, totalmem } from "node:os";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { BabyMenuServerContext } from "@babymenu/contracts";

const execFileAsync = promisify(execFile);

const CPU_BASELINE_TABLE = "system_usage_cpu_baseline";
const GITHUB_CONTRIBUTIONS_CACHE_TABLE = "system_usage_github_contributions_cache";
const MINI_MAC_HOST = "mac-mini";
const REMOTE_CACHE_MS = 30_000;
const GPU_CACHE_MS = 300_000;
const GITHUB_CACHE_MS = 60 * 60_000;
const GITHUB_CONTRIBUTIONS_SOURCE_VERSION = 4;
const GITHUB_CONTRIBUTION_WEEKS = 26;
const GITHUB_HISTORY_BUFFER_DAYS = 7;
const GITHUB_LOGIN_FALLBACK = "camilojourney";
const GITHUB_AUTHOR_EMAIL_FALLBACK = "juancamilomabe@gmail.com";
const GITHUB_AUTHOR_EMAILS = [
  GITHUB_AUTHOR_EMAIL_FALLBACK,
  "JUAN.MARTINEZBENAVIDES@baruchmail.cuny.edu",
  "127817036+camilojourney@users.noreply.github.com",
  "camilojourney@users.noreply.github.com",
] as const;
const GITHUB_GRAPHQL_REPOSITORY_PAGE_SIZE = 50;
const GITHUB_GRAPHQL_HISTORY_PAGE_SIZE = 100;
const GITHUB_CLI_TIMEOUT_MS = 30_000;
const GH_BIN_CANDIDATES = [process.env.GH_BIN, "/opt/homebrew/bin/gh", "/usr/local/bin/gh", "gh"].filter(Boolean) as string[];
const GIT_BIN_CANDIDATES = [process.env.GIT_BIN, "/opt/homebrew/bin/git", "/usr/bin/git", "git"].filter(Boolean) as string[];

type RemoteSystemSample = {
  status: "online" | "offline";
  cpuPercent: number | null;
  memoryPercent: number | null;
  storagePercent: number | null;
  capacity: MachineCapacity;
  gpuSummary: string | null;
};

type MachineCapacity = {
  cpu: string;
  memory: string;
  storage: string;
  gpu: string | null;
};

type HeatmapCell = {
  date: string;
  level: 0 | 1 | 2 | 3 | 4;
  count: number | null;
};

type WeeklyContributionTotal = {
  start: string;
  end: string;
  total: number;
};

type GitHubContributions = {
  status: "live" | "stale" | "unavailable";
  login: string;
  weeks: number;
  cells: HeatmapCell[][];
  weeklyTotals: WeeklyContributionTotal[];
  todayCount: number | null;
  currentWeekTotal: number | null;
  totalContributions: number | null;
  rangeStart: string | null;
  rangeEnd: string | null;
  fetchedAt: number | null;
  error: string | null;
};

let remoteCache: { expiresAt: number; sample: RemoteSystemSample } | null = null;
let remoteInFlight: Promise<RemoteSystemSample> | null = null;
let gpuCache: { expiresAt: number; summary: string | null } | null = null;
let githubCache: { expiresAt: number; contributions: GitHubContributions } | null = null;
let githubInFlight: Promise<GitHubContributions> | null = null;

function readCpuTotals() {
  let idle = 0;
  let total = 0;
  for (const core of cpus()) {
    const t = core.times;
    idle += t.idle;
    total += t.user + t.nice + t.sys + t.idle + t.irq;
  }
  return { idle, total };
}

function readCpuPercent(context: BabyMenuServerContext): number | null {
  context.db.exec(
    `CREATE TABLE IF NOT EXISTS ${CPU_BASELINE_TABLE} (id INTEGER PRIMARY KEY CHECK (id = 1), idle INTEGER NOT NULL, total INTEGER NOT NULL)`,
  );
  const { idle, total } = readCpuTotals();
  const prev = context.db.get<{ idle: number; total: number }>(
    `SELECT idle, total FROM ${CPU_BASELINE_TABLE} WHERE id = 1`,
  );
  context.db.run(
    `INSERT INTO ${CPU_BASELINE_TABLE} (id, idle, total) VALUES (1, ?, ?)
     ON CONFLICT(id) DO UPDATE SET idle = excluded.idle, total = excluded.total`,
    [idle, total],
  );
  if (!prev) return null;
  const idleDelta = idle - prev.idle;
  const totalDelta = total - prev.total;
  if (totalDelta <= 0) return null;
  const busyRatio = 1 - idleDelta / totalDelta;
  return Math.min(100, Math.max(0, busyRatio * 100));
}

function parsePageCount(vmStatOutput: string, label: string): number {
  const match = vmStatOutput.match(new RegExp(`${label}:\\s+(\\d+)\\.`));
  return match ? Number(match[1]) : 0;
}

function parseStoragePercent(dfOutput: string): number | null {
  const line = dfOutput.trim().split("\n").at(-1);
  if (!line) return null;
  const match = line.match(/\s(\d{1,3})%\s/);
  if (!match) return null;
  return Math.min(100, Math.max(0, Number(match[1])));
}

function parseStorageCapacity(dfOutput: string): string {
  const line = dfOutput.trim().split("\n").at(-1);
  if (!line) return "--";
  const blocks = Number(line.trim().split(/\s+/)[1]);
  return Number.isFinite(blocks) ? formatBytes(blocks * 1024) : "--";
}

function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) return "--";
  const units = ["B", "KB", "MB", "GB", "TB"] as const;
  let value = bytes;
  let unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  const precision = value >= 100 || Number.isInteger(value) ? 0 : 1;
  return `${value.toFixed(precision)} ${units[unitIndex]}`;
}

function memoryPercentFromVmStat(vmStatOutput: string, memoryBytes: number): number | null {
  if (!Number.isFinite(memoryBytes) || memoryBytes <= 0) return null;
  const pageSizeMatch = vmStatOutput.match(/page size of (\d+) bytes/);
  const pageSize = pageSizeMatch ? Number(pageSizeMatch[1]) : 4096;
  const free = parsePageCount(vmStatOutput, "Pages free");
  const inactive = parsePageCount(vmStatOutput, "Pages inactive");
  const speculative = parsePageCount(vmStatOutput, "Pages speculative");
  const purgeable = parsePageCount(vmStatOutput, "Pages purgeable");
  const reclaimableBytes = (free + inactive + speculative + purgeable) * pageSize;
  const usedBytes = Math.max(0, memoryBytes - reclaimableBytes);
  return Math.min(100, Math.max(0, (usedBytes / memoryBytes) * 100));
}

async function readMemoryPercent(): Promise<number> {
  const { stdout } = await execFileAsync("vm_stat");
  return memoryPercentFromVmStat(stdout, totalmem()) ?? 0;
}

async function readStoragePercent(): Promise<number | null> {
  const { stdout } = await execFileAsync("df", ["-k", "/"]);
  return parseStoragePercent(stdout);
}

async function readLocalCapacity(): Promise<MachineCapacity> {
  const [dfResult, cpuBrandResult, gpuResult] = await Promise.allSettled([
    execFileAsync("df", ["-k", "/"]),
    execFileAsync("sysctl", ["-n", "machdep.cpu.brand_string"]),
    execFileAsync("system_profiler", ["SPDisplaysDataType"], { timeout: 5000, maxBuffer: 128 * 1024 }),
  ]);
  const cpuBrand =
    cpuBrandResult.status === "fulfilled" ? cpuBrandResult.value.stdout.trim().replace(/\s+/g, " ") : "";

  return {
    cpu: cpuBrand || `${cpus().length} cores`,
    memory: formatBytes(totalmem()),
    storage: dfResult.status === "fulfilled" ? parseStorageCapacity(dfResult.value.stdout) : "--",
    gpu: gpuResult.status === "fulfilled" ? parseGpuSummary(gpuResult.value.stdout) : null,
  };
}

function ymd(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function addDays(date: Date, days: number): Date {
  const next = new Date(date);
  next.setDate(next.getDate() + days);
  return next;
}

function startOfWeekSunday(date: Date): Date {
  const next = new Date(date);
  next.setHours(0, 0, 0, 0);
  next.setDate(next.getDate() - next.getDay());
  return next;
}

function endOfDay(date: Date): Date {
  const next = new Date(date);
  next.setHours(23, 59, 59, 999);
  return next;
}

function ensureGitHubTables(context: BabyMenuServerContext) {
  context.db.exec(
    `CREATE TABLE IF NOT EXISTS ${GITHUB_CONTRIBUTIONS_CACHE_TABLE} (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      json TEXT NOT NULL,
      fetched_at INTEGER NOT NULL,
      source_version INTEGER NOT NULL DEFAULT ${GITHUB_CONTRIBUTIONS_SOURCE_VERSION}
    )`,
  );
  const columns = context.db.query<{ name: string }>(`PRAGMA table_info(${GITHUB_CONTRIBUTIONS_CACHE_TABLE})`);
  if (!columns.some((column) => column.name === "source_version")) {
    context.db.exec(
      `ALTER TABLE ${GITHUB_CONTRIBUTIONS_CACHE_TABLE}
       ADD COLUMN source_version INTEGER NOT NULL DEFAULT 0`,
    );
  }
}

function unavailableGitHubContributions(error: string | null): GitHubContributions {
  return {
    status: "unavailable",
    login: GITHUB_LOGIN_FALLBACK,
    weeks: GITHUB_CONTRIBUTION_WEEKS,
    cells: Array.from({ length: 7 }, () => []),
    weeklyTotals: [],
    todayCount: null,
    currentWeekTotal: null,
    totalContributions: null,
    rangeStart: null,
    rangeEnd: null,
    fetchedAt: null,
    error,
  };
}

function persistGitHubContributions(context: BabyMenuServerContext, contributions: GitHubContributions) {
  ensureGitHubTables(context);
  context.db.run(
    `INSERT INTO ${GITHUB_CONTRIBUTIONS_CACHE_TABLE} (id, json, fetched_at, source_version) VALUES (1, ?, ?, ?)
     ON CONFLICT(id) DO UPDATE SET json = excluded.json, fetched_at = excluded.fetched_at, source_version = excluded.source_version`,
    [JSON.stringify(contributions), contributions.fetchedAt ?? Date.now(), GITHUB_CONTRIBUTIONS_SOURCE_VERSION],
  );
}

function readCachedGitHubContributions(
  context: BabyMenuServerContext,
  options: { error: string | null; maxAgeMs?: number; stale: boolean },
): GitHubContributions | null {
  ensureGitHubTables(context);
  const row = context.db.get<{ json: string; fetched_at: number; source_version: number }>(
    `SELECT json, fetched_at, source_version FROM ${GITHUB_CONTRIBUTIONS_CACHE_TABLE} WHERE id = 1`,
  );
  if (!row) return null;
  try {
    if (row.source_version !== GITHUB_CONTRIBUTIONS_SOURCE_VERSION) return null;
    const cacheAgeMs = Date.now() - row.fetched_at;
    if (options.maxAgeMs !== undefined && (cacheAgeMs < 0 || cacheAgeMs > options.maxAgeMs)) {
      return null;
    }
    const cached = JSON.parse(row.json) as GitHubContributions;
    if (cached.weeks < GITHUB_CONTRIBUTION_WEEKS) return null;
    if (!Array.isArray(cached.weeklyTotals) || cached.weeklyTotals.length < GITHUB_CONTRIBUTION_WEEKS) return null;
    if (!Array.isArray(cached.cells) || cached.cells.some((row) => !Array.isArray(row) || row.length < GITHUB_CONTRIBUTION_WEEKS)) return null;
    const weeklyTotals = cached.weeklyTotals.slice(-GITHUB_CONTRIBUTION_WEEKS);
    const cells = cached.cells.map((cellRow) => cellRow.slice(-GITHUB_CONTRIBUTION_WEEKS));
    const rangeStart = weeklyTotals.find((week) => week.start)?.start ?? null;
    const rangeEnd = [...weeklyTotals].reverse().find((week) => week.end)?.end ?? null;
    return {
      ...cached,
      status: options.stale ? "stale" : "live",
      weeks: weeklyTotals.length,
      cells,
      weeklyTotals,
      rangeStart,
      rangeEnd,
      fetchedAt: row.fetched_at,
      error: options.stale ? options.error : cached.error,
    };
  } catch {
    return null;
  }
}

type GitHubGraphqlPageInfo = {
  hasNextPage?: boolean | null;
  endCursor?: string | null;
};

type GitHubGraphqlGitActor = {
  email?: string | null;
  user?: { login?: string | null } | null;
};

type GitHubCommitResponse = {
  oid?: string;
  authoredDate?: string | null;
  committedDate?: string | null;
  author?: GitHubGraphqlGitActor | null;
  committer?: GitHubGraphqlGitActor | null;
};

type GitHubGraphqlCommitHistory = {
  totalCount?: number | null;
  pageInfo?: GitHubGraphqlPageInfo | null;
  nodes?: Array<GitHubCommitResponse | null> | null;
};

type GitHubGraphqlRepositoryNode = {
  nameWithOwner?: string | null;
  isArchived?: boolean | null;
  isDisabled?: boolean | null;
  pushedAt?: string | null;
  defaultBranchRef?: {
    name?: string | null;
    target?: { history?: GitHubGraphqlCommitHistory | null } | null;
  } | null;
};

type GitHubCommitHistory = {
  repo: string;
  commits: GitHubCommitResponse[];
};

type GitHubRepositoriesGraphqlResponse = {
  data?: {
    viewer?: {
      login?: string | null;
      repositories?: {
        nodes?: Array<GitHubGraphqlRepositoryNode | null> | null;
        pageInfo?: GitHubGraphqlPageInfo | null;
      } | null;
    } | null;
  } | null;
};

type GitHubHistoryGraphqlResponse = {
  data?: {
    repository?: {
      object?: {
        history?: GitHubGraphqlCommitHistory | null;
      } | null;
    } | null;
  } | null;
};

async function runGitHubCli(args: string[]): Promise<string> {
  let lastError: unknown = null;
  for (const bin of GH_BIN_CANDIDATES) {
    try {
      const { stdout } = await execFileAsync(bin, args, {
        timeout: GITHUB_CLI_TIMEOUT_MS,
        maxBuffer: 8 * 1024 * 1024,
        env: { ...process.env, GH_PROMPT_DISABLED: "1", NO_COLOR: "1" },
      });
      return stdout;
    } catch (error) {
      lastError = error;
      if ((error as { code?: unknown }).code !== "ENOENT") break;
    }
  }
  throw lastError ?? new Error("GitHub CLI unavailable");
}

function splitRepositoryName(fullName: string) {
  const [owner, repo] = fullName.split("/");
  if (!owner || !repo) throw new Error(`Invalid GitHub repo name: ${fullName}`);
  return { owner, repo };
}

async function runGitHubGraphql<T>(
  query: string,
  fields: Record<string, string | number | string[] | null | undefined> = {},
): Promise<T> {
  const args = ["api", "graphql", "-f", `query=${query}`];
  for (const [key, value] of Object.entries(fields)) {
    if (value === null || value === undefined) continue;
    if (Array.isArray(value)) {
      for (const item of value) args.push("-f", `${key}[]=${item}`);
      continue;
    }
    args.push("-F", `${key}=${value}`);
  }
  return JSON.parse(await runGitHubCli(args)) as T;
}

async function runGitCli(args: string[]): Promise<string | null> {
  for (const bin of GIT_BIN_CANDIDATES) {
    try {
      const { stdout } = await execFileAsync(bin, args, {
        timeout: 5000,
        maxBuffer: 64 * 1024,
        env: { ...process.env, NO_COLOR: "1" },
      });
      const value = stdout.trim();
      return value || null;
    } catch (error) {
      if ((error as { code?: unknown }).code !== "ENOENT") return null;
    }
  }
  return null;
}

async function readAuthenticatedGitHubLogin(): Promise<string> {
  const response = await runGitHubGraphql<{ data?: { viewer?: { login?: string | null } | null } | null }>(
    "query { viewer { login } }",
  );
  return response.data?.viewer?.login || GITHUB_LOGIN_FALLBACK;
}

async function readGitHubAuthorEmails(login: string): Promise<string[]> {
  const localEmail = await runGitCli(["config", "--get", "user.email"]);
  return Array.from(
    new Set([
      ...GITHUB_AUTHOR_EMAILS,
      localEmail && localEmail.includes("@") ? localEmail : null,
      `${login}@users.noreply.github.com`,
    ].filter((email): email is string => Boolean(email))),
  );
}

function pushedInsideRange(pushedAt: string | null | undefined, fromIso: string) {
  if (!pushedAt) return true;
  return Date.parse(pushedAt) >= Date.parse(fromIso);
}

function commitNodes(history: GitHubGraphqlCommitHistory | null | undefined): GitHubCommitResponse[] {
  return (history?.nodes ?? []).filter((commit): commit is GitHubCommitResponse => Boolean(commit?.oid));
}

const GITHUB_REPOSITORIES_WITH_HISTORY_QUERY = `
  query($after: String, $from: GitTimestamp!, $to: GitTimestamp!, $emails: [String!], $repoPageSize: Int!, $historyPageSize: Int!) {
    viewer {
      login
      repositories(first: $repoPageSize, after: $after, affiliations: [OWNER, COLLABORATOR, ORGANIZATION_MEMBER], orderBy: { field: PUSHED_AT, direction: DESC }) {
        pageInfo {
          hasNextPage
          endCursor
        }
        nodes {
          nameWithOwner
          isArchived
          isDisabled
          pushedAt
          defaultBranchRef {
            name
            target {
              ... on Commit {
                history(first: $historyPageSize, since: $from, until: $to, author: { emails: $emails }) {
                  totalCount
                  pageInfo {
                    hasNextPage
                    endCursor
                  }
                  nodes {
                    oid
                    authoredDate
                    committedDate
                    author {
                      email
                      user {
                        login
                      }
                    }
                    committer {
                      email
                      user {
                        login
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
`;

const GITHUB_REPOSITORY_HISTORY_PAGE_QUERY = `
  query($owner: String!, $repo: String!, $expression: String!, $after: String, $from: GitTimestamp!, $to: GitTimestamp!, $emails: [String!], $historyPageSize: Int!) {
    repository(owner: $owner, name: $repo) {
      object(expression: $expression) {
        ... on Commit {
          history(first: $historyPageSize, after: $after, since: $from, until: $to, author: { emails: $emails }) {
            totalCount
            pageInfo {
              hasNextPage
              endCursor
            }
            nodes {
              oid
              authoredDate
              committedDate
              author {
                email
                user {
                  login
                }
              }
              committer {
                email
                user {
                  login
                }
              }
            }
          }
        }
      }
    }
  }
`;

async function fetchRemainingDefaultBranchCommits(
  fullName: string,
  defaultBranch: string,
  firstPage: GitHubGraphqlCommitHistory | null | undefined,
  emails: string[],
  fromIso: string,
  toIso: string,
): Promise<GitHubCommitResponse[]> {
  const commits = commitNodes(firstPage);
  let cursor = firstPage?.pageInfo?.endCursor ?? null;

  while (firstPage?.pageInfo?.hasNextPage && cursor) {
    const { owner, repo } = splitRepositoryName(fullName);
    const response = await runGitHubGraphql<GitHubHistoryGraphqlResponse>(GITHUB_REPOSITORY_HISTORY_PAGE_QUERY, {
      owner,
      repo,
      expression: defaultBranch,
      after: cursor,
      from: fromIso,
      to: toIso,
      emails,
      historyPageSize: GITHUB_GRAPHQL_HISTORY_PAGE_SIZE,
    });
    const history = response.data?.repository?.object?.history;
    commits.push(...commitNodes(history));
    if (!history?.pageInfo?.hasNextPage || !history.pageInfo.endCursor) break;
    cursor = history.pageInfo.endCursor;
    firstPage = history;
  }

  return commits;
}

async function fetchDefaultBranchHistories(emails: string[], fromIso: string, toIso: string) {
  const histories: GitHubCommitHistory[] = [];
  let failures = 0;
  let repositoryCursor: string | null = null;

  while (true) {
    const response = await runGitHubGraphql<GitHubRepositoriesGraphqlResponse>(GITHUB_REPOSITORIES_WITH_HISTORY_QUERY, {
      after: repositoryCursor,
      from: fromIso,
      to: toIso,
      emails,
      repoPageSize: GITHUB_GRAPHQL_REPOSITORY_PAGE_SIZE,
      historyPageSize: GITHUB_GRAPHQL_HISTORY_PAGE_SIZE,
    });
    const repositories = response.data?.viewer?.repositories;
    const nodes = repositories?.nodes ?? [];
    if (!repositories) throw new Error("GitHub GraphQL repositories unavailable");

    let recentRepositoriesInPage = 0;
    for (const node of nodes) {
      if (!node?.nameWithOwner || node.isArchived || node.isDisabled || !pushedInsideRange(node.pushedAt, fromIso)) continue;
      recentRepositoriesInPage += 1;
      const defaultBranch = node.defaultBranchRef?.name;
      const firstPage = node.defaultBranchRef?.target?.history;
      if (!defaultBranch || !firstPage) continue;

      try {
        histories.push({
          repo: node.nameWithOwner,
          commits: await fetchRemainingDefaultBranchCommits(node.nameWithOwner, defaultBranch, firstPage, emails, fromIso, toIso),
        });
      } catch {
        failures += 1;
        histories.push({ repo: node.nameWithOwner, commits: commitNodes(firstPage) });
      }
    }

    if (!repositories.pageInfo?.hasNextPage || !repositories.pageInfo.endCursor || (nodes.length > 0 && recentRepositoriesInPage === 0)) {
      break;
    }
    repositoryCursor = repositories.pageInfo.endCursor;
  }

  return { histories, failures };
}

function quartileAt(sortedValues: number[], percentile: number): number {
  if (sortedValues.length === 0) return 0;
  const index = Math.min(sortedValues.length - 1, Math.max(0, Math.ceil(sortedValues.length * percentile) - 1));
  return sortedValues[index];
}

function levelFromCommitCount(count: number, quartiles: { lower: number; middle: number; upper: number }): 0 | 1 | 2 | 3 | 4 {
  if (count <= 0) return 0;
  if (count <= quartiles.lower) return 1;
  if (count <= quartiles.middle) return 2;
  if (count <= quartiles.upper) return 3;
  return 4;
}

function normalizeGitHubCommitHistories(login: string, histories: GitHubCommitHistory[], failures: number, fetchedAt: number): GitHubContributions {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const todayKey = ymd(today);
  const start = startOfWeekSunday(addDays(today, -(GITHUB_CONTRIBUTION_WEEKS - 1) * 7));
  const countsByDate = new Map<string, number>();
  const seenShas = new Set<string>();

  for (const history of histories) {
    for (const commit of history.commits) {
      if (!commit.oid || seenShas.has(commit.oid)) continue;
      const commitDate = commit.authoredDate ?? commit.committedDate;
      if (!commitDate) continue;
      const day = commitDate.slice(0, 10);
      seenShas.add(commit.oid);
      countsByDate.set(day, (countsByDate.get(day) ?? 0) + 1);
    }
  }

  const nonzeroDailyCounts = [...countsByDate.values()].filter((count) => count > 0).sort((a, b) => a - b);
  const quartiles = {
    lower: quartileAt(nonzeroDailyCounts, 0.25),
    middle: quartileAt(nonzeroDailyCounts, 0.5),
    upper: quartileAt(nonzeroDailyCounts, 0.75),
  };
  const cells: HeatmapCell[][] = Array.from({ length: 7 }, () => []);
  const weeklyTotals: WeeklyContributionTotal[] = [];
  let todayCount: number | null = null;
  let totalContributions = 0;

  for (let weekIndex = 0; weekIndex < GITHUB_CONTRIBUTION_WEEKS; weekIndex += 1) {
    let total = 0;
    let weekStart = "";
    let weekEnd = "";

    for (let weekday = 0; weekday < 7; weekday += 1) {
      const date = addDays(start, weekIndex * 7 + weekday);
      const dateKey = ymd(date);
      const isFuture = date > today;
      const count = isFuture ? null : countsByDate.get(dateKey) ?? 0;
      if (weekday === 0) weekStart = dateKey;
      if (!isFuture) weekEnd = dateKey;
      if (count !== null) {
        total += count;
        totalContributions += count;
      }
      if (dateKey === todayKey) todayCount = count;
      cells[weekday].push({
        date: dateKey,
        count,
        level: count === null ? 0 : levelFromCommitCount(count, quartiles),
      });
    }

    weeklyTotals.push({ start: weekStart, end: weekEnd || weekStart, total });
  }

  return {
    status: "live",
    login,
    weeks: GITHUB_CONTRIBUTION_WEEKS,
    cells,
    weeklyTotals,
    todayCount,
    currentWeekTotal: weeklyTotals.at(-1)?.total ?? null,
    totalContributions,
    rangeStart: weeklyTotals.at(0)?.start ?? null,
    rangeEnd: todayKey,
    fetchedAt,
    error: failures > 0 ? `commit history skipped ${failures} repo${failures === 1 ? "" : "s"}` : null,
  };
}

async function fetchGitHubContributions(): Promise<GitHubContributions> {
  const now = new Date();
  const visibleStart = startOfWeekSunday(addDays(now, -(GITHUB_CONTRIBUTION_WEEKS - 1) * 7));
  const from = `${ymd(addDays(visibleStart, -GITHUB_HISTORY_BUFFER_DAYS))}T00:00:00Z`;
  const to = `${ymd(endOfDay(now))}T23:59:59Z`;
  const login = await readAuthenticatedGitHubLogin();
  const emails = await readGitHubAuthorEmails(login);
  const { histories, failures } = await fetchDefaultBranchHistories(emails, from, to);
  if (histories.length === 0) throw new Error("GitHub default-branch commit histories unavailable");
  return normalizeGitHubCommitHistories(login, histories, failures, Date.now());
}

async function readGitHubContributions(context: BabyMenuServerContext): Promise<GitHubContributions> {
  if (githubCache && githubCache.expiresAt > Date.now()) return githubCache.contributions;
  if (githubInFlight) return githubInFlight;
  const cached = readCachedGitHubContributions(context, { error: null, maxAgeMs: GITHUB_CACHE_MS, stale: false });
  if (cached) {
    githubCache = { contributions: cached, expiresAt: Date.now() + GITHUB_CACHE_MS };
    return cached;
  }

  const inFlight = fetchGitHubContributions()
    .then((contributions) => {
      persistGitHubContributions(context, contributions);
      githubCache = { contributions, expiresAt: Date.now() + GITHUB_CACHE_MS };
      return contributions;
    })
    .catch((error) => {
      const message = error instanceof Error && error.message ? error.message : "GitHub contributions unavailable";
      const staleCached = readCachedGitHubContributions(context, { error: message, stale: true });
      const fallback = staleCached ?? unavailableGitHubContributions(message);
      githubCache = { contributions: fallback, expiresAt: Date.now() + REMOTE_CACHE_MS };
      return fallback;
    })
    .finally(() => {
      githubInFlight = null;
    });
  githubInFlight = inFlight;
  return inFlight;
}

const REMOTE_SAMPLE_COMMAND = [
  "export LC_ALL=C",
  "printf '__DISK__\\n'",
  "df -k / | tail -n 1",
  "printf '__MEMSIZE__\\n'",
  "sysctl -n hw.memsize",
  "printf '__CPUBRAND__\\n'",
  "sysctl -n machdep.cpu.brand_string 2>/dev/null || true",
  "printf '__VMSTAT__\\n'",
  "vm_stat",
  "printf '__CPU__\\n'",
  "sysctl -n hw.ncpu",
  "ps -A -o %cpu= | awk '{sum += $1} END {printf \"%.6f\\n\", sum}'",
  "printf '__GPU__\\n'",
  "system_profiler SPDisplaysDataType 2>/dev/null | egrep 'Chipset Model|Total Number of Cores|Metal Support' || true",
].join("; ");

function sectionAfter(output: string, marker: string, nextMarker?: string): string | null {
  const start = output.indexOf(marker);
  if (start === -1) return null;
  const contentStart = start + marker.length;
  const end = nextMarker ? output.indexOf(nextMarker, contentStart) : output.length;
  return output.slice(contentStart, end === -1 ? output.length : end).trim();
}

function parseGpuSummary(output: string): string | null {
  const block = sectionAfter(output, "__GPU__") ?? output;
  if (!block) return null;
  const model = block.match(/Chipset Model:\s*(.+)/)?.[1]?.trim();
  const cores = block.match(/Total Number of Cores:\s*(\d+)/)?.[1]?.trim();
  const metal = block.match(/Metal Support:\s*(.+)/)?.[1]?.trim();
  const parts = [model, cores ? `${cores} cores` : null, metal].filter(Boolean);
  return parts.length > 0 ? parts.join(" · ") : null;
}

function parseRemoteSample(output: string): RemoteSystemSample | null {
  const disk = sectionAfter(output, "__DISK__", "__MEMSIZE__");
  const memorySize = sectionAfter(output, "__MEMSIZE__", "__CPUBRAND__");
  const cpuBrand = sectionAfter(output, "__CPUBRAND__", "__VMSTAT__");
  const vmStat = sectionAfter(output, "__VMSTAT__", "__CPU__");
  const cpu = sectionAfter(output, "__CPU__", "__GPU__");
  const gpu = sectionAfter(output, "__GPU__");
  if (!disk || !memorySize || !vmStat || !cpu) return null;

  const cpuParts = cpu.split(/\s+/).map(Number);
  if (cpuParts.length < 2 || cpuParts.some((value) => !Number.isFinite(value))) return null;
  const cpuCoreCount = cpuParts[0];
  const gpuSummary = parseGpuSummary(output);
  return {
    status: "online",
    storagePercent: parseStoragePercent(disk),
    memoryPercent: memoryPercentFromVmStat(vmStat, Number(memorySize)),
    cpuPercent: Math.min(100, Math.max(0, cpuParts[1] / cpuParts[0])),
    capacity: {
      cpu: cpuBrand || `${cpuCoreCount} cores`,
      memory: formatBytes(Number(memorySize)),
      storage: parseStorageCapacity(disk),
      gpu: gpuSummary,
    },
    gpuSummary,
  };
}

function offlineRemoteSample(): RemoteSystemSample {
  return {
    status: "offline",
    cpuPercent: null,
    memoryPercent: null,
    storagePercent: null,
    capacity: {
      cpu: "Apple M4",
      memory: "16 GB",
      storage: "228 GB",
      gpu: gpuCache && gpuCache.expiresAt > Date.now() ? gpuCache.summary : "Apple M4 · 10 cores · Metal 4",
    },
    gpuSummary: gpuCache && gpuCache.expiresAt > Date.now() ? gpuCache.summary : null,
  };
}

async function readRemoteSystem(): Promise<RemoteSystemSample> {
  if (remoteCache && remoteCache.expiresAt > Date.now()) return remoteCache.sample;
  if (remoteInFlight) return remoteInFlight;

  const inFlight = execFileAsync(
    "ssh",
    ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "-o", "StrictHostKeyChecking=yes", MINI_MAC_HOST, REMOTE_SAMPLE_COMMAND],
    { timeout: 7000, maxBuffer: 64 * 1024 },
  )
    .then(({ stdout }) => parseRemoteSample(stdout) ?? offlineRemoteSample())
    .catch(() => offlineRemoteSample())
    .then((sample) => {
      if (sample.gpuSummary) gpuCache = { summary: sample.gpuSummary, expiresAt: Date.now() + GPU_CACHE_MS };
      remoteCache = { sample, expiresAt: Date.now() + REMOTE_CACHE_MS };
      return sample;
    })
    .finally(() => {
      remoteInFlight = null;
    });
  remoteInFlight = inFlight;
  return inFlight;
}

export const background = {
  intervalMs: 3_600_000,
  runOnStart: true,
  run: async (context: BabyMenuServerContext) => {
    await readGitHubContributions(context);
  },
};

export const actions = {
  sample: async (_input: unknown, context: BabyMenuServerContext) => {
    const [memoryPercent, cpuPercent, storagePercent, capacity, miniMac, githubContributions] = await Promise.all([
      readMemoryPercent(),
      Promise.resolve(readCpuPercent(context)),
      readStoragePercent(),
      readLocalCapacity(),
      readRemoteSystem(),
      readGitHubContributions(context),
    ]);

    return { cpuPercent, memoryPercent, storagePercent, capacity, miniMac, githubContributions };
  },
};
