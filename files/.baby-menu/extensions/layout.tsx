import type { BabyMenuLayoutProps } from "@babymenu/contracts";

const columns = [
  ["codex-quota", "claude-code-quota"],
  ["grok-quota", "antigravity-quota"],
  ["deepseek-quota", "system-usage"],
] as const;

export default function Layout({ widgets, renderWidget }: BabyMenuLayoutProps) {
  const available = new Set(widgets.map((widget) => widget.id));

  return (
    <div className="grid w-[1080px] grid-cols-3 items-start gap-x-5 gap-y-4 p-4">
      {columns.map((column, columnIndex) => (
        <div key={columnIndex} className="flex min-w-0 flex-col gap-4">
          {column.map((id) =>
            available.has(id) ? (
              <section key={id} className="min-w-0 rounded-md border border-line-faint bg-elevated p-3">
                {renderWidget(id)}
              </section>
            ) : null,
          )}
        </div>
      ))}
    </div>
  );
}
