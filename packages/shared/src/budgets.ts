/** Data and size budgets from the Phase 3 proposal §4.3 and §8. Bytes are transfer sizes. */

const KB = 1024;
const MB = 1024 * KB;

export const BUDGETS = {
  /** First install: title + prologue, Low tier. */
  firstInstallLow: 3 * MB,
  firstInstallMedium: 6 * MB,
  /** Per district, first visit. */
  districtLow: 250 * KB,
  districtMedium: 500 * KB,
  districtHigh: 1.2 * MB,
  /** Idle network use while playing. */
  idlePerHour: 1 * MB,
  /** Typical 30-minute session on Low. */
  sessionLow30min: 10 * MB,
  /** Initial JS (gzip) for the client shell. */
  initialJsGzip: 600 * KB,
} as const;

export function formatBytes(n: number): string {
  if (n < KB) return `${n} B`;
  if (n < MB) return `${(n / KB).toFixed(1)} KB`;
  return `${(n / MB).toFixed(2)} MB`;
}
