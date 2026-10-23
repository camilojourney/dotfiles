import type { HTMLAttributes, ReactNode } from "react";
import { Badge, StatusDot } from "@babymenu/ui";
import { QUOTA_STYLES, TEXT_STYLES, QUOTA_FILL_STYLES, QUOTA_VALUE_STYLES, QUOTA_EXHAUSTED_STYLES, quotaTone, type QuotaTone } from "./ui-styles";

type QuotaRowProps = Omit<HTMLAttributes<HTMLElement>, "className" | "children"> & {
  name: string;
  plan?: string;
  tone?: "live" | "warn" | "danger" | "muted";
  hint?: string;
  children: ReactNode;
};

export function QuotaRow({ name, plan, tone = "live", hint, children, ...attributes }: QuotaRowProps) {
  return (
    <article className={QUOTA_STYLES.row} {...attributes}>
      <div className="min-w-0">
        <div className={TEXT_STYLES.label}>{name}</div>
        <div className={QUOTA_STYLES.status}>
          {plan && <Badge tone="neutral">{plan}</Badge>}
          <StatusDot tone={tone} />
          {hint}
        </div>
      </div>
      <div className={QUOTA_STYLES.content}>{children}</div>
    </article>
  );
}

type QuotaValueProps = { value: ReactNode; unit?: string; label?: string; tone?: QuotaTone };

export function QuotaValue({ value, unit, label = "left", tone = "live" }: QuotaValueProps) {
  return (
    <div className="min-w-0 text-right">
      <strong className={`flex justify-end ${TEXT_STYLES.value} ${QUOTA_VALUE_STYLES[tone]}`}>
        {value}
        {unit && <span className={TEXT_STYLES.unit}>{unit}</span>}
      </strong>
      <span className={TEXT_STYLES.valueLabel}>{label}</span>
    </div>
  );
}

type QuotaWindowRowProps = {
  label: string;
  reset?: string;
  remaining: number;
  tone?: QuotaTone;
  note?: string;
  children?: ReactNode;
};

export function QuotaWindowRow({ label, reset, remaining, tone = quotaTone(remaining), note, children }: QuotaWindowRowProps) {
  const clamped = Math.max(0, Math.min(100, remaining));
  const exhausted = clamped === 0;
  return (
    <div className={QUOTA_STYLES.window}>
      <div className="min-w-0">
        <div className={QUOTA_STYLES.heading}>
          <span className="min-w-0 truncate" title={label}>{label}</span>
          <span className={QUOTA_STYLES.reset}>{reset ?? "active"}</span>
        </div>
        {/* A zero quota gets a red exhaustion marker, not a full remaining meter. */}
        <div role={exhausted ? "img" : "progressbar"} aria-label={exhausted ? `${label}: no quota remaining` : `${label} remaining`} aria-valuenow={exhausted ? undefined : clamped} aria-valuemin={exhausted ? undefined : 0} aria-valuemax={exhausted ? undefined : 100} className={`${QUOTA_STYLES.track} ${exhausted ? QUOTA_EXHAUSTED_STYLES.track : ""}`}>
          <div className={`${QUOTA_STYLES.fill} ${QUOTA_FILL_STYLES[tone]}`} style={{ width: `${clamped}%` }} />
        </div>
        {note && <div className={QUOTA_STYLES.note}>{note}</div>}
      </div>
      {children ?? <span />}
    </div>
  );
}
