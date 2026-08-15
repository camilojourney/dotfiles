import { Tooltip } from "@babymenu/ui";
import { useSystemUsage } from "./store";

const RADIUS = 15.9155;
const CIRCUMFERENCE = 2 * Math.PI * RADIUS;
const SYSTEM_GAUGE_SIZE = 60;
const HEATMAP_LABEL_COLUMN_PX = 24;
const HEATMAP_GAP_PX = 3;
const WEEKDAY_LABELS = ["", "Mon", "", "Wed", "", "Fri", ""];
const MONTH_LABELS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const LEVEL_CLASSES = {
  0: "bg-[rgba(255,255,255,.045)]",
  1: "bg-[rgba(106,227,182,.18)]",
  2: "bg-[rgba(106,227,182,.38)]",
  3: "bg-[rgba(106,227,182,.64)]",
  4: "bg-signal-live",
} as const;

function toneFor(value: number | null, warnAt: number, dangerAt: number) {
  if (value === null) return "live" as const;
  if (value >= dangerAt) return "danger" as const;
  if (value >= warnAt) return "warn" as const;
  return "live" as const;
}

function toneClass(tone: "live" | "warn" | "danger") {
  if (tone === "danger") return "text-signal-danger";
  if (tone === "warn") return "text-signal-warn";
  return "text-signal-live";
}

function formatPercent(value: number | null) {
  return value === null ? "--" : String(Math.round(value));
}

function formatScore(value: number | null) {
  if (value === null) return "--";
  return value >= 1000 ? `${(value / 1000).toFixed(1)}k` : String(Math.round(value));
}

function formatDelta(value: number) {
  if (value === 0) return "0";
  const prefix = value > 0 ? "+" : "-";
  return `${prefix}${formatScore(Math.abs(value))}`;
}

function formatDateLabel(value: string | null) {
  if (!value) return "";
  const date = new Date(`${value}T12:00:00`);
  return date.toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

function formatTooltipDate(value: string) {
  const date = new Date(`${value}T12:00:00`);
  return date.toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" });
}

function formatExactCommitCount(count: number) {
  return `${count.toLocaleString()} ${count === 1 ? "commit" : "commits"}`;
}

function dailyCommitTooltipText(cell: GitHubContributions["cells"][number][number]) {
  if (cell.count === null) return `${formatTooltipDate(cell.date)} · future day`;
  return `${formatTooltipDate(cell.date)} · ${formatExactCommitCount(cell.count)} on default branches`;
}

function weeklyCommitTooltipText(week: GitHubContributions["weeklyTotals"][number]) {
  return `${formatTooltipDate(week.start)} to ${formatTooltipDate(week.end)} · ${formatExactCommitCount(week.total)} on default branches`;
}

function CommitCountTooltip({ date, count }: { date: string; count: number }) {
  return (
    <span className="block min-w-[148px]">
      <span className="block whitespace-nowrap font-mono text-sm leading-none tracking-value text-ink-strong">{formatExactCommitCount(count)}</span>
      <span className="mt-1 block whitespace-nowrap text-[9px] uppercase tracking-caps text-ink-muted">{date}</span>
    </span>
  );
}

function FutureDayTooltip({ date }: { date: string }) {
  return (
    <span className="block min-w-[96px]">
      <span className="block whitespace-nowrap font-mono text-sm leading-none tracking-value text-ink-strong">Future day</span>
      <span className="mt-1 block whitespace-nowrap text-[9px] uppercase tracking-caps text-ink-muted">{date}</span>
    </span>
  );
}

function dailyCommitTooltipContent(cell: GitHubContributions["cells"][number][number]) {
  if (cell.count === null) return <FutureDayTooltip date={formatTooltipDate(cell.date)} />;
  return <CommitCountTooltip date={formatTooltipDate(cell.date)} count={cell.count} />;
}

function weeklyCommitTooltipContent(week: GitHubContributions["weeklyTotals"][number]) {
  return <CommitCountTooltip date={`${formatTooltipDate(week.start)} to ${formatTooltipDate(week.end)}`} count={week.total} />;
}

function monthIndex(value: string) {
  const date = new Date(`${value}T12:00:00`);
  const month = date.getMonth();
  return Number.isFinite(month) ? month : null;
}

function contributionMonthLabels(weeks: GitHubContributions["weeklyTotals"]) {
  let previousMonth: number | null = null;
  const labels: Array<{ index: number; endIndex: number; isCurrent: boolean; label: string }> = [];

  weeks.forEach((week, index) => {
    const month = week.start ? monthIndex(week.start) : null;
    if (month !== null && month !== previousMonth) {
      const previousLabel = labels.at(-1);
      if (previousLabel) previousLabel.endIndex = index;
      labels.push({ index, endIndex: weeks.length, isCurrent: false, label: MONTH_LABELS[month] });
    }
    if (month !== null) previousMonth = month;
  });

  const currentLabel = labels.at(-1);
  if (currentLabel) currentLabel.isCurrent = true;

  return labels.filter(({ index, endIndex, isCurrent }) => isCurrent || endIndex - index >= 2);
}

function contributionStatusLabel(status: "live" | "stale" | "unavailable") {
  if (status === "live") return "github commits live";
  if (status === "stale") return "github commits stale";
  return "github unavailable";
}

function RadialGauge({ value, tone, size = SYSTEM_GAUGE_SIZE }: { value: number | null; tone: "live" | "warn" | "danger"; size?: number }) {
  const clamped = value === null ? 0 : Math.max(0, Math.min(100, value));
  const dash = (clamped / 100) * CIRCUMFERENCE;

  return (
    <div className="relative shrink-0" style={{ width: size, height: size }}>
      <svg viewBox="0 0 36 36" className="-rotate-90" style={{ width: size, height: size }}>
        <circle cx="18" cy="18" r={RADIUS} fill="none" stroke="currentColor" strokeWidth="3" className="text-ink-soft opacity-20" />
        <circle
          cx="18"
          cy="18"
          r={RADIUS}
          fill="none"
          stroke="currentColor"
          strokeWidth="3"
          strokeLinecap="round"
          strokeDasharray={`${dash} ${CIRCUMFERENCE - dash}`}
          className={toneClass(tone)}
        />
      </svg>
      <div className="absolute inset-0 flex items-center justify-center">
        <span className="text-lg font-light tracking-value text-ink-strong">{formatPercent(value)}</span>
        {value !== null && <span className="ml-0.5 mt-2 text-xs text-ink-soft">%</span>}
      </div>
    </div>
  );
}

function Metric({ label, value, warnAt, dangerAt }: { label: string; value: number | null; warnAt: number; dangerAt: number }) {
  const tone = toneFor(value, warnAt, dangerAt);
  return (
    <div className="flex min-w-0 flex-col items-center gap-1.5">
      <RadialGauge value={value} tone={tone} />
      <span className="text-xxs uppercase tracking-caps text-ink-label">{label}</span>
    </div>
  );
}

function MachineCard({
  name,
  badge,
  cpuPercent,
  memoryPercent,
  storagePercent,
  capacity,
  status = "online",
  gpuSummary,
}: {
  name: string;
  badge: string;
  cpuPercent: number | null;
  memoryPercent: number | null;
  storagePercent: number | null;
  capacity: {
    cpu: string;
    memory: string;
    storage: string;
    gpu: string | null;
  };
  status?: "online" | "offline";
  gpuSummary?: string | null;
}) {
  return (
    <article className="min-w-0 rounded-sm border border-line-faint bg-[rgba(255,255,255,.015)] p-2.5">
      <div className="mb-2 flex items-center justify-between gap-2">
        <span className="truncate text-xxs uppercase tracking-caps text-ink-soft">{name}</span>
        <span className={`rounded-pill border border-line-faint px-1.5 py-0.5 text-[8px] uppercase tracking-caps ${status === "online" ? "text-ink-label" : "text-signal-danger"}`}>
          {badge}
        </span>
      </div>

      {status === "online" ? (
        <>
          <div className="grid grid-cols-3 gap-2">
            <Metric label="cpu" value={cpuPercent} warnAt={60} dangerAt={85} />
            <Metric label="mem" value={memoryPercent} warnAt={75} dangerAt={90} />
            <Metric label="disk" value={storagePercent} warnAt={75} dangerAt={90} />
          </div>
          <CapacityStrip capacity={capacity} gpuSummary={gpuSummary} />
        </>
      ) : (
        <>
          <div className="grid min-h-[82px] place-items-center rounded-sm border border-dashed border-[rgba(255,106,122,.25)] text-center text-xxs uppercase tracking-caps text-signal-danger">
            ssh target unavailable
          </div>
          <CapacityStrip capacity={capacity} gpuSummary={gpuSummary} />
        </>
      )}
    </article>
  );
}

type GitHubContributions = ReturnType<typeof useSystemUsage>["githubContributions"];

function CapacityStrip({ capacity, gpuSummary }: { capacity: { cpu: string; memory: string; storage: string; gpu: string | null }; gpuSummary?: string | null }) {
  const gpu = gpuSummary ?? capacity.gpu;
  return (
    <div className="mt-2 border-t border-line-faint pt-2">
      <div className="grid grid-cols-3 gap-1.5 text-[9px]">
        <CapacityItem label="cpu" value={capacity.cpu} />
        <CapacityItem label="ram" value={capacity.memory} />
        <CapacityItem label="disk" value={capacity.storage} />
      </div>
      {gpu && <div className="mt-1.5 truncate font-mono text-[9px] text-ink-label">{gpu}</div>}
    </div>
  );
}

function CapacityItem({ label, value }: { label: string; value: string }) {
  return (
    <div className="min-w-0 rounded-[3px] border border-line-faint bg-[rgba(255,255,255,.018)] px-1.5 py-1">
      <div className="text-[8px] uppercase tracking-caps text-ink-muted">{label}</div>
      <div className="truncate font-mono text-[9px] text-ink-label">{value}</div>
    </div>
  );
}

function WeeklyComparison({ weeks, login }: { weeks: GitHubContributions["weeklyTotals"]; login: string }) {
  const current = weeks.at(-1);
  const previous = weeks.at(-2);
  const delta = current && previous ? current.total - previous.total : null;

  return (
    <div className="mt-3 rounded-sm border border-line-faint bg-[rgba(255,255,255,.015)] p-2">
      <div className="mb-2 flex items-center justify-between gap-2 text-[9px] uppercase tracking-caps text-ink-label">
        <span>real github weekly comparison</span>
        <span className="truncate text-ink-soft">gh default branches @{login}</span>
      </div>
      <div className="grid grid-cols-3 gap-1.5">
        <ComparisonMetric label="this week" value={current ? formatScore(current.total) : "--"} />
        <ComparisonMetric label="previous" value={previous ? formatScore(previous.total) : "--"} />
        <ComparisonMetric label="delta" value={delta === null ? "--" : formatDelta(delta)} tone={delta === null || delta === 0 ? "neutral" : delta > 0 ? "live" : "danger"} />
      </div>
    </div>
  );
}

function ComparisonMetric({ label, value, tone = "neutral" }: { label: string; value: string; tone?: "neutral" | "live" | "danger" }) {
  const toneClasses = {
    neutral: "text-ink-strong",
    live: "text-signal-live",
    danger: "text-signal-danger",
  } as const;

  return (
    <div className="min-w-0">
      <div className="text-[8px] uppercase tracking-caps text-ink-muted">{label}</div>
      <div className={`truncate font-mono text-sm tracking-value ${toneClasses[tone]}`}>{value}</div>
    </div>
  );
}

function WeeklyBars({ weeks }: { weeks: GitHubContributions["weeklyTotals"] }) {
  const maxTotal = Math.max(1, ...weeks.map((week) => week.total));
  if (weeks.length === 0) return null;

  return (
    <div className="mt-3 border-t border-line-faint pt-2">
      <div className="mb-1.5 flex items-center justify-between text-[9px] uppercase tracking-caps text-ink-label">
        <span>weekly bars</span>
        <span>{formatScore(maxTotal)} max</span>
      </div>
      <div className="grid w-full" style={{ columnGap: HEATMAP_GAP_PX, gridTemplateColumns: heatmapGridColumns(weeks.length) }}>
        <span />
        {weeks.map((week) => {
          const height = week.total === 0 ? 2 : Math.max(5, (week.total / maxTotal) * 100);
          const tooltip = weeklyCommitTooltipText(week);
          return (
            <span key={`${week.start}-${week.end}`} className="flex min-w-0 flex-col items-center gap-1">
              <Tooltip content={weeklyCommitTooltipContent(week)} side="top" className="max-w-none">
                <span className="flex h-9 w-full items-end justify-center" aria-label={tooltip}>
                  <i className="block w-full rounded-t-[2px] bg-signal-live" style={{ height: `${height}%`, opacity: week.total === 0 ? 0.22 : 0.9 }} />
                </span>
              </Tooltip>
            </span>
          );
        })}
      </div>
    </div>
  );
}

function heatmapGridColumns(weeks: number) {
  return `${HEATMAP_LABEL_COLUMN_PX}px repeat(${weeks}, minmax(0, 1fr))`;
}

function Heatmap({ githubContributions }: { githubContributions: GitHubContributions }) {
  const firstDay = githubContributions.rangeStart;
  const lastDay = githubContributions.rangeEnd;
  const hasContributions = githubContributions.weeklyTotals.length > 0;
  const heatmapColumns = heatmapGridColumns(githubContributions.weeks);
  const monthLabels = contributionMonthLabels(githubContributions.weeklyTotals);

  return (
    <div>
      <div className="my-2 flex items-baseline justify-between gap-3">
        <div>
          <span className="font-mono text-lg tracking-value text-ink-strong">{formatScore(githubContributions.currentWeekTotal)}</span>
          <span className="ml-1 text-xxs text-ink-soft">this week</span>
        </div>
        <span className={githubContributions.status === "unavailable" ? "text-xxs text-signal-danger" : "text-xxs text-ink-soft"}>
          {contributionStatusLabel(githubContributions.status)}
        </span>
      </div>

      {hasContributions ? (
        <div className="w-full min-w-0 pb-0.5">
          <div className="mb-1 grid w-full text-[10px] font-medium text-ink-soft opacity-80" style={{ columnGap: HEATMAP_GAP_PX, gridTemplateColumns: heatmapColumns }}>
            <span />
            {monthLabels.map(({ index, endIndex, isCurrent, label }) => (
              <span key={`${index}-${label}`} className={`min-w-0 leading-3 ${isCurrent ? "text-right" : ""}`} style={{ gridColumn: `${index + 2} / ${endIndex + 2}` }}>
                {label}
              </span>
            ))}
          </div>
          <div className="grid w-full" style={{ columnGap: HEATMAP_GAP_PX, gridTemplateColumns: heatmapColumns, rowGap: HEATMAP_GAP_PX }}>
            {WEEKDAY_LABELS.map((label, index) => (
              <span key={index} className="flex items-center justify-end text-right text-[9px] leading-none text-ink-soft opacity-50" style={{ gridColumn: 1, gridRow: index + 1 }}>
                {label}
              </span>
            ))}
            {githubContributions.cells.map((row, rowIndex) =>
              row.map((cell, weekIndex) => {
                const tooltip = dailyCommitTooltipText(cell);
                return (
                  <span key={`${cell.date}-${rowIndex}-${weekIndex}`} className="aspect-square w-full min-w-0" style={{ gridColumn: weekIndex + 2, gridRow: rowIndex + 1 }}>
                    <Tooltip content={dailyCommitTooltipContent(cell)} side="top" className="max-w-none">
                      <span aria-label={tooltip} className={`block h-full w-full rounded-[2px] border border-[rgba(255,255,255,.025)] ${LEVEL_CLASSES[cell.level]}`} />
                    </Tooltip>
                  </span>
                );
              }),
            )}
          </div>
        </div>
      ) : (
        <div className="grid min-h-[92px] place-items-center rounded-sm border border-dashed border-line-faint px-3 text-center text-xxs uppercase tracking-caps text-ink-muted">
          github contribution data unavailable
        </div>
      )}

      <WeeklyComparison weeks={githubContributions.weeklyTotals} login={githubContributions.login} />
      <WeeklyBars weeks={githubContributions.weeklyTotals} />

      <div className="mt-2 flex items-center justify-between gap-3 text-[9px] text-ink-label">
        <span className="truncate">
          {firstDay && lastDay ? `${formatDateLabel(firstDay)} to ${formatDateLabel(lastDay)} · today ${formatScore(githubContributions.todayCount)}` : "warming up history"}
        </span>
        <span className="flex items-center gap-1">
          less
          <i className={`h-2.5 w-2.5 rounded-[2px] ${LEVEL_CLASSES[0]}`} />
          <i className={`h-2.5 w-2.5 rounded-[2px] ${LEVEL_CLASSES[1]}`} />
          <i className={`h-2.5 w-2.5 rounded-[2px] ${LEVEL_CLASSES[2]}`} />
          <i className={`h-2.5 w-2.5 rounded-[2px] ${LEVEL_CLASSES[3]}`} />
          <i className={`h-2.5 w-2.5 rounded-[2px] ${LEVEL_CLASSES[4]}`} />
          more
        </span>
      </div>
      {githubContributions.status !== "live" && githubContributions.error && <div className="mt-1 truncate text-[9px] text-ink-soft">{githubContributions.error}</div>}
    </div>
  );
}
export function SystemUsageView() {
  const { cpuPercent, memoryPercent, storagePercent, capacity, miniMac, githubContributions } = useSystemUsage();

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between border-b border-line-faint pb-2 text-[10px] font-medium uppercase tracking-[0.08em] text-ink-label">
        <span>fleet / github</span>
        <span>last 6 months</span>
      </div>

      <Heatmap githubContributions={githubContributions} />

      <div className="border-t border-line-faint pt-3">
        <div className="mb-2 flex items-center justify-between text-xxs uppercase tracking-caps text-ink-label">
          <span>systems</span>
          <span className={miniMac.status === "online" ? "text-signal-live" : "text-ink-muted"}>mini {miniMac.status}</span>
        </div>
        <div className="grid grid-cols-2 gap-2.5">
          <MachineCard name="MacBook Pro" badge="local" cpuPercent={cpuPercent} memoryPercent={memoryPercent} storagePercent={storagePercent} capacity={capacity} />
          <MachineCard
            name="Mac mini"
            badge={miniMac.status}
            status={miniMac.status}
            cpuPercent={miniMac.cpuPercent}
            memoryPercent={miniMac.memoryPercent}
            storagePercent={miniMac.storagePercent}
            capacity={miniMac.capacity}
            gpuSummary={miniMac.gpuSummary}
          />
        </div>
      </div>
    </div>
  );
}
