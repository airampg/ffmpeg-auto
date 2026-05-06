import clsx from "clsx";

interface Props {
  percent: number | null;
  showLabel?: boolean;
}

export function ProgressBar({ percent, showLabel = true }: Props) {
  const indeterminate = percent == null;
  const clamped = percent != null ? Math.min(Math.max(percent, 0), 100) : 0;

  return (
    <div className="space-y-1.5">
      <div className="relative h-2 w-full bg-[var(--surface-1)] border border-[var(--border-subtle)] rounded-full overflow-hidden">
        {indeterminate ? (
          <div className="absolute inset-y-0 left-0 w-1/3 progress-running rounded-full" />
        ) : (
          <div
            className={clsx(
              "h-full rounded-full transition-[width] duration-500 ease-out",
              clamped >= 100 ? "bg-emerald-500" : "progress-running"
            )}
            style={{ width: `${clamped}%` }}
          />
        )}
      </div>
      {showLabel && (
        <div className="flex items-center justify-between text-[11px]">
          <span className="text-zinc-500">
            {indeterminate ? "Working…" : clamped >= 100 ? "Complete" : "In progress"}
          </span>
          {!indeterminate && (
            <span className="font-mono text-zinc-400">{clamped.toFixed(1)}%</span>
          )}
        </div>
      )}
    </div>
  );
}
