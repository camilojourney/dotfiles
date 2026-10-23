export type CodexQuotaSnapshot = {
  source: string;
  accountEmail?: string;
  plan?: string;
  windows: Array<{
    id: string;
    label: string;
    percentUsed: number;
    resetAt?: string;
  }>;
  refreshedAt: string;
  stale: boolean;
};

export type QuotaResult<T> = { ok: true; data: T } | { ok: false; error: string; sourceTried: string[] };
