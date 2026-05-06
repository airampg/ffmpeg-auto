import { useEffect, useState } from "react";
import type { JobStatus } from "../api/types";

export interface LogState {
  lines: string[];
  progress: { percent: number | null; currentTimeSeconds: number | null; totalDurationSeconds: number | null };
  status: JobStatus | null;
  ended: boolean;
}

const INITIAL: LogState = {
  lines: [],
  progress: { percent: null, currentTimeSeconds: null, totalDurationSeconds: null },
  status: null,
  ended: false
};

const MAX_LINES = 5000;

export function useJobLogs(jobId: string | undefined): LogState {
  const [state, setState] = useState<LogState>(INITIAL);

  useEffect(() => {
    if (!jobId) {
      setState(INITIAL);
      return;
    }
    setState(INITIAL);
    const source = new EventSource(`/api/v1/jobs/${jobId}/logs`);

    source.addEventListener("log", (event) => {
      try {
        const data = JSON.parse((event as MessageEvent).data) as { line: string };
        setState((prev) => {
          const nextLines = prev.lines.concat(data.line.split(/\r?\n/).filter((s) => s.length > 0));
          if (nextLines.length > MAX_LINES) {
            nextLines.splice(0, nextLines.length - MAX_LINES);
          }
          return { ...prev, lines: nextLines };
        });
      } catch {
        // ignore malformed event
      }
    });

    source.addEventListener("progress", (event) => {
      try {
        const data = JSON.parse((event as MessageEvent).data) as LogState["progress"];
        setState((prev) => ({ ...prev, progress: data }));
      } catch { /* ignore */ }
    });

    source.addEventListener("status", (event) => {
      try {
        const data = JSON.parse((event as MessageEvent).data) as { status: JobStatus };
        setState((prev) => ({ ...prev, status: data.status }));
      } catch { /* ignore */ }
    });

    source.addEventListener("end", () => {
      setState((prev) => ({ ...prev, ended: true }));
      source.close();
    });

    source.onerror = () => {
      // Browser auto-reconnects. If the server closed because job ended, we already received `end`.
    };

    return () => {
      source.close();
    };
  }, [jobId]);

  return state;
}
