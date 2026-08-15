import type { BabyMenuLayoutProps } from "@babymenu/contracts";

const quotaWidgetIds = [
  "codex-quota",
  "claude-code-quota",
  "deepseek-quota",
  "grok-quota",
  "antigravity-quota",
] as const;

const SYSTEM_WIDGET_ID = "system-usage";

export default function Layout({ widgets, renderWidget }: BabyMenuLayoutProps) {
  const available = new Set(widgets.map((widget) => widget.id));
  const quotaIds = quotaWidgetIds.filter((id) => available.has(id));
  const renderedIds = new Set<string>([...quotaIds, SYSTEM_WIDGET_ID]);
  const remainingWidgets = widgets.filter((widget) => !renderedIds.has(widget.id));

  return (
    <div className="w-[1080px] bg-stage p-3">
      <div className="flex items-center justify-between border-b border-line-faint px-1 pb-2 text-xxs uppercase tracking-caps text-ink-label">
        <span>baby menu / fleet</span>
        <span>live sources</span>
      </div>

      <div className="grid grid-cols-[minmax(0,1.08fr)_minmax(0,0.92fr)] items-start gap-3 pt-3">
        <section className="min-w-0 rounded-md border border-line-faint bg-elevated p-3">
          <div className="flex items-center justify-between border-b border-line-faint pb-2 text-xxs uppercase tracking-caps text-ink-label">
            <span>quotas / remaining</span>
            <span className="text-signal-live">live</span>
          </div>
          <div className="divide-y divide-line-faint">
            {quotaIds.map((id) => (
              <div key={id}>{renderWidget(id)}</div>
            ))}
          </div>
        </section>

        {available.has(SYSTEM_WIDGET_ID) && (
          <section className="min-w-0 rounded-md border border-line-faint bg-elevated p-3">
            {renderWidget(SYSTEM_WIDGET_ID)}
          </section>
        )}
      </div>

      {remainingWidgets.length > 0 && (
        <div className="grid grid-cols-3 gap-3 pt-3">
          {remainingWidgets.map((widget) => (
            <section key={widget.id} className="min-w-0 rounded-md border border-line-faint bg-elevated p-3">
              {renderWidget(widget.id)}
            </section>
          ))}
        </div>
      )}
    </div>
  );
}
