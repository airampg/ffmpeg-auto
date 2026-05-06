import clsx from "clsx";

export function ProgressBar({ percent }: { percent: number | null }) {
  if (percent == null) {
    return (
      <div className="h-2 w-full bg-zinc-800 rounded overflow-hidden">
        <div className="h-full w-1/3 bg-accent animate-pulse" />
      </div>
    );
  }
  const clamped = Math.min(Math.max(percent, 0), 100);
  return (
    <div className="h-2 w-full bg-zinc-800 rounded overflow-hidden">
      <div
        className={clsx("h-full bg-accent transition-all")}
        style={{ width: `${clamped}%` }}
      />
    </div>
  );
}
