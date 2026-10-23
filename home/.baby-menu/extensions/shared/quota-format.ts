export function formatQuotaReset(resetAt?: string, resetText?: string): string | undefined {
  if (resetText) return resetText;
  if (!resetAt) return undefined;
  const date = new Date(resetAt);
  if (Number.isNaN(date.getTime())) return undefined;
  return "resets " + date.toLocaleString(undefined, { weekday: "short", hour: "numeric", minute: "2-digit" });
}
