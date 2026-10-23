// One hierarchy for every widget. Extension-local shared symlinks keep these
// modules compatible with the packaged compiler without copying the styles.
export const TYPE_SCALE = {
  metadata: "text-xxs",
  label: "text-xs",
  content: "text-sm",
  value: "text-2xl",
} as const;

export const TEXT_STYLES = {
  label: `truncate ${TYPE_SCALE.label} uppercase tracking-caps text-ink-strong`,
  content: `${TYPE_SCALE.content} text-ink-muted`,
  metadata: `${TYPE_SCALE.metadata} text-ink-label`,
  value: `font-mono ${TYPE_SCALE.value} font-normal leading-none tracking-value`,
  indicatorValue: `${TYPE_SCALE.content} font-light tracking-value text-ink-strong`,
  indicatorLabel: `${TYPE_SCALE.metadata} uppercase tracking-caps text-ink-label`,
  unit: `ml-0.5 mt-0.5 ${TYPE_SCALE.label} opacity-45`,
  valueLabel: `mt-1 block ${TYPE_SCALE.metadata} uppercase tracking-caps text-ink-label`,
} as const;

export const QUOTA_STYLES = {
  row: "grid grid-cols-[86px_minmax(0,1fr)_72px] items-center gap-3 py-2",
  content: "col-span-2 flex min-w-0 flex-col gap-2",
  window: "grid grid-cols-[minmax(0,1fr)_72px] items-center gap-3",
  heading: `mb-1 flex justify-between gap-2 ${TYPE_SCALE.metadata} text-ink-soft`,
  reset: "shrink-0 whitespace-nowrap text-ink-label",
  status: `mt-1 flex items-center gap-1.5 ${TYPE_SCALE.metadata} text-ink-label`,
  note: `mt-1 ${TYPE_SCALE.metadata} text-ink-label`,
  track: "h-[7px] overflow-hidden rounded-[2px] border border-line-faint bg-pressed",
  fill: "h-full rounded-[1px]",
} as const;

export const PANEL_STYLES = {
  widget: "min-w-0 rounded-md border-2 border-line bg-elevated p-3",
  machine: "min-w-0 rounded-sm border-2 border-line bg-[rgba(255,255,255,.015)] p-2.5",
} as const;

export const QUOTA_EXHAUSTED_STYLES = {
  track: "border-0 bg-signal-danger",
} as const;

export const SYSTEM_GAUGE_SIZE = 48;
export type QuotaTone = "live" | "warn" | "danger";

export const QUOTA_FILL_STYLES: Record<QuotaTone, string> = {
  live: "bg-signal-live", warn: "bg-signal-warn", danger: "bg-signal-danger",
};
export const QUOTA_VALUE_STYLES: Record<QuotaTone, string> = {
  live: "text-ink-strong", warn: "text-signal-warn", danger: "text-signal-danger",
};

export function quotaTone(remaining: number): QuotaTone {
  if (remaining <= 10) return "danger";
  if (remaining <= 30) return "warn";
  return "live";
}
