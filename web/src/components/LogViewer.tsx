import { useEffect, useRef } from "react";

export function LogViewer({ lines }: { lines: string[] }) {
  const ref = useRef<HTMLDivElement>(null);
  const stickyRef = useRef(true);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    if (stickyRef.current) {
      el.scrollTop = el.scrollHeight;
    }
  }, [lines]);

  const onScroll = (event: React.UIEvent<HTMLDivElement>) => {
    const el = event.currentTarget;
    const distanceFromBottom = el.scrollHeight - el.scrollTop - el.clientHeight;
    stickyRef.current = distanceFromBottom < 24;
  };

  return (
    <div
      ref={ref}
      onScroll={onScroll}
      className="font-mono text-xs leading-relaxed text-zinc-200 bg-zinc-900 rounded p-3 h-96 overflow-y-auto whitespace-pre-wrap break-all"
    >
      {lines.length === 0
        ? <span className="text-zinc-500">Waiting for ffmpeg output…</span>
        : lines.map((line, idx) => {
            const isError = /\b(Error|failed|invalid|Unable)\b/i.test(line);
            return (
              <div key={idx} className={isError ? "text-rose-400" : undefined}>
                {line}
              </div>
            );
          })}
    </div>
  );
}
