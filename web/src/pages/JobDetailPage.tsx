import { useEffect } from "react";
import { Link, useParams } from "react-router-dom";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useJob } from "../hooks/useJob";
import { useJobLogs } from "../hooks/useJobLogs";
import { LogViewer } from "../components/LogViewer";
import { ProgressBar } from "../components/ProgressBar";
import { StatusBadge } from "../components/StatusBadge";
import { OutputsList } from "../components/OutputsList";
import { deleteJob } from "../api/jobs";
import { formatDate, formatSeconds } from "../lib/format";

export function JobDetailPage() {
  const { id } = useParams<{ id: string }>();
  const job = useJob(id);
  const logs = useJobLogs(id);
  const queryClient = useQueryClient();

  useEffect(() => {
    if (logs.ended || (logs.status && ["succeeded", "failed", "cancelled"].includes(logs.status))) {
      queryClient.invalidateQueries({ queryKey: ["job", id] });
      queryClient.invalidateQueries({ queryKey: ["jobs"] });
    }
  }, [logs.ended, logs.status, id, queryClient]);

  const cancelMutation = useMutation({
    mutationFn: () => deleteJob(id as string),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["jobs"] });
      queryClient.invalidateQueries({ queryKey: ["job", id] });
    }
  });

  if (job.isLoading) return <p className="p-6 text-sm text-zinc-500">Loading…</p>;
  if (job.error) return <p className="p-6 text-sm text-rose-400">Could not load job.</p>;
  if (!job.data) return <p className="p-6 text-sm text-zinc-500">Job not found.</p>;

  const data = job.data;
  const liveProgress = logs.progress.percent != null ? logs.progress : data.progress;

  return (
    <div className="max-w-5xl mx-auto p-6 space-y-6">
      <div>
        <Link to="/" className="text-xs text-zinc-400 hover:text-accent">← Back</Link>
      </div>

      <header className="space-y-2">
        <div className="flex items-center gap-3">
          <h1 className="text-xl font-semibold font-mono">{data.jobId.slice(0, 8)}</h1>
          <StatusBadge status={(logs.status ?? data.status) as typeof data.status} />
        </div>
        <p className="text-sm text-zinc-400">{data.inputFilename}</p>
        <div className="text-xs text-zinc-500 grid grid-cols-2 md:grid-cols-4 gap-2">
          <div>Created: {formatDate(data.createdAt)}</div>
          <div>Started: {formatDate(data.startedAt)}</div>
          <div>Finished: {formatDate(data.finishedAt)}</div>
          <div>
            {liveProgress.currentTimeSeconds != null
              ? `${formatSeconds(liveProgress.currentTimeSeconds)} / ${formatSeconds(liveProgress.totalDurationSeconds ?? data.progress.totalDurationSeconds)}`
              : "—"}
          </div>
        </div>
      </header>

      <ProgressBar percent={liveProgress.percent} />

      {data.command && (
        <details className="bg-zinc-900 rounded p-3 text-xs font-mono">
          <summary className="cursor-pointer text-zinc-400">ffmpeg command</summary>
          <pre className="mt-2 whitespace-pre-wrap break-all text-zinc-300">{data.command}</pre>
        </details>
      )}

      {data.errorMessage && (
        <div className="rounded bg-rose-500/10 border border-rose-500/30 p-3 text-sm text-rose-300">
          {data.errorMessage}
        </div>
      )}

      <section>
        <h2 className="text-sm uppercase tracking-wide text-zinc-400 mb-2">Logs</h2>
        <LogViewer lines={logs.lines} />
      </section>

      <section>
        <h2 className="text-sm uppercase tracking-wide text-zinc-400 mb-2">Outputs</h2>
        <OutputsList jobId={data.jobId} outputs={data.outputs} />
      </section>

      <div className="flex gap-2">
        <button
          type="button"
          onClick={() => cancelMutation.mutate()}
          disabled={cancelMutation.isPending}
          className="text-xs text-zinc-400 hover:text-rose-400 underline"
        >
          {(["queued", "running"] as const).includes((logs.status ?? data.status) as "queued" | "running")
            ? "Cancel job"
            : "Delete job + files"}
        </button>
      </div>
    </div>
  );
}
