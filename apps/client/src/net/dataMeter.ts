/**
 * Counts network bytes the game uses this session (proposal §8: data meter and daily cap).
 * HTTP comes from Resource Timing transferSize (0 when served from cache, which is what we want).
 * Realtime sockets report their own bytes through addSocketBytes().
 */
type Listener = (bytes: number) => void;

let httpBytes = 0;
let socketBytes = 0;
const startedAt = performance.now();
const listeners = new Set<Listener>();

function notify() {
  const total = httpBytes + socketBytes;
  listeners.forEach((l) => l(total));
}

export function startDataMeter(): void {
  // Count what already loaded before the observer started (the page itself and boot assets).
  const nav = performance.getEntriesByType('navigation')[0] as PerformanceNavigationTiming | undefined;
  httpBytes += nav?.transferSize ?? 0;
  for (const e of performance.getEntriesByType('resource') as PerformanceResourceTiming[]) {
    httpBytes += e.transferSize || 0;
  }
  try {
    const po = new PerformanceObserver((list) => {
      for (const e of list.getEntries() as PerformanceResourceTiming[]) httpBytes += e.transferSize || 0;
      notify();
    });
    po.observe({ type: 'resource', buffered: false });
  } catch {
    /* very old browsers: meter shows boot bytes only */
  }
  // Resource Timing buffer defaults to 250 entries; raise it so long sessions keep counting.
  try { performance.setResourceTimingBufferSize(2000); } catch { /* ignore */ }
  notify();
}

export function addSocketBytes(n: number): void {
  socketBytes += n;
  notify();
}

export const dataMeter = {
  total: () => httpBytes + socketBytes,
  minutes: () => (performance.now() - startedAt) / 60000,
  subscribe(l: Listener) {
    listeners.add(l);
    l(httpBytes + socketBytes);
    return () => listeners.delete(l);
  },
};
