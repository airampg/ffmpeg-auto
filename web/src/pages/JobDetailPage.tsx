import { useEffect } from "react";
import { Link, useParams } from "react-router-dom";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useJob } from "../hooks/useJob";
import { useJobLogs } from "../hooks/useJobLogs";
import { LogViewer } from "../components/LogViewer";
import { ProgressBar } from "../components/ProgressBar";
import { StatusBadge } from "../components/StatusBadge";
import { OutputsList } from "../components/OutputsList";
import { AppShell } from "../components/AppShell";
import { deleteJob } from "../api/jobs";
import { formatDate, formatSeconds } from "../lib/format";
import {
  ChevronLeftIcon,
  TrashIcon,
  XIcon,
  TerminalIcon,
  AlertIcon
} from "../lib/icons";

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

  if (job.isLoading) {
    return (
      <AppShell>
        <div className="surface-card p-8 text-sm text-zinc-500 text-center">Loading…</div>
      </AppShell>
    );
  }
  if (job.error) {
    return (
      <AppShell>
        <div className="rounded-xl bg-rose-500/[0.07] border border-rose-500/25 p-4 text-sm text-rose-200">
          Could not load job.
        </div>
      </AppShell>
    );
  }
  if (!job.data) {
    return (
      <AppShell>
        <div className="surface-card p-8 text-sm text-zinc-500 text-center">Job not found.</div>
      </AppShell>
    );
  }

  const data = job.data;
  const liveProgress = logs.progress.percent != null ? logs.progress : data.progress;
  const status = (logs.status ?? data.status) as typeof data.status;
  const isActive = (["queued", "running"] as const).includes(status as "queued" | "running");

  return (
    <AppShell>
      <div className="space-y-6">
        <Link
          to="/"
          className="inline-flex items-center gap-1.5 text-xs text-zinc-500 hover:text-zinc-200 transition-colors"
        >
          <ChevronLeftIcon size={14} />
          Back to jobs
        </Link>

        <div className="surface-card p-6 space-y-5">
          <header className="flex flex-wrap items-start justify-between gap-3">
            <div className="space-y-1.5 min-w-0 flex-1">
              <div className="flex items-center gap-2.5 flex-wrap">
                <h1 className="text-lg font-semibold text-zinc-100 truncate">{data.inputFilename}</h1>
                <StatusBadge status={status} size="md" />
              </div>
              <p className="text-xs font-mono text-zinc-500">{data.jobId}</p>
            </div>
            <div className="flex items-center gap-2 flex-shrink-0">
              <button
                type="button"
                onClick={() => cancelMutation.mutate()}
                disabled={cancelMutation.isPending}
                className={isActive ? "btn-ghost inline-flex items-center gap-1.5 text-xs" : "btn-danger inline-flex items-center gap-1.5 text-xs"}
              >
                {isActive ? <XIcon size={12} /> : <TrashIcon size={12} />}
                {isActive ? "Cancel job" : "Delete"}
              </button>
            </div>
          </header>

          <ProgressBar percent={liveProgress.percent} />

          <dl className="grid grid-cols-2 md:grid-cols-4 gap-x-6 gap-y-3 pt-2 border-t border-white/[0.05]">
            <Stat label="Created" value={formatDate(data.createdAt)} />
            <Stat label="Started" value={formatDate(data.startedAt)} />
            <Stat label="Finished" value={formatDate(data.finishedAt)} />
            <Stat
              label="Time"
              value={
                liveProgress.currentTimeSeconds != null
                  ? `${formatSeconds(liveProgress.currentTimeSeconds)} / ${formatSeconds(liveProgress.totalDurationSeconds ?? data.progress.totalDurationSeconds)}`
                  : "—"
              }
              mono
            />
          </dl>
        </div>

        {data.errorMessage && (
          <div className="rounded-xl bg-rose-500/[0.07] border border-rose-500/25 px-4 py-3 flex items-start gap-3">
            <AlertIcon size={18} className="text-rose-400 flex-shrink-0 mt-0.5" />
            <div className="text-sm text-rose-200 break-words">{data.errorMessage}</div>
          </div>
        )}

        {data.command && (
          <details className="surface-card group overflow-hidden" open>
            <summary className="px-4 py-3 cursor-pointer flex items-center gap-2.5 hover:bg-[var(--surface-2)] transition-colors list-none">
              <TerminalIcon size={14} className="text-zinc-400" />
              <span className="text-sm font-medium text-zinc-200 flex-1">ffmpeg command</span>
              <span className="text-[10px] uppercase tracking-wider text-zinc-500 group-open:hidden">show</span>
              <span className="text-[10px] uppercase tracking-wider text-zinc-500 hidden group-open:inline">hide</span>
            </summary>
            <pre className="px-4 pb-4 text-xs font-mono text-zinc-300 whitespace-pre-wrap break-all border-t border-white/[0.05] pt-3">
              {data.command}
            </pre>
          </details>
        )}

        <section className="space-y-3">
          <SectionLabel title="Logs" subtitle={logs.lines.length > 0 ? `${logs.lines.length} lines` : undefined} live={status === "running"} />
          <LogViewer lines={logs.lines} live={status === "running"} />
        </section>

        <section className="space-y-3">
          <SectionLabel title="Outputs" subtitle={data.outputs.length > 0 ? `${data.outputs.length} files` : undefined} />
          <OutputsList jobId={data.jobId} outputs={data.outputs} />
        </section>
      </div>
    </AppShell>
  );
}

function Stat({ label, value, mono }: { label: string; value: string | null | undefined; mono?: boolean }) {
  return (
    <div>
      <dt className="text-[10px] uppercase tracking-[0.2em] text-zinc-500 font-medium">{label}</dt>
      <dd className={mono ? "font-mono text-sm text-zinc-300 mt-0.5" : "text-sm text-zinc-300 mt-0.5"}>
        {value ?? "—"}
      </dd>
    </div>
  );
}

function SectionLabel({ title, subtitle, live }: { title: string; subtitle?: string; live?: boolean }) {
  return (
    <div className="flex items-baseline justify-between gap-3">
      <div className="flex items-center gap-2">
        <h2 className="text-[11px] uppercase tracking-[0.2em] text-zinc-400 font-medium">{title}</h2>
        {live && (
          <span className="inline-flex items-center gap-1 text-[10px] text-emerald-400 uppercase tracking-wider">
            <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse-soft" />
            live
          </span>
        )}
      </div>
      {subtitle && <span className="text-xs text-zinc-500">{subtitle}</span>}
    </div>
  );
}
