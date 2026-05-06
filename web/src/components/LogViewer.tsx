import { useEffect, useRef, useState } from "react";
import clsx from "clsx";
import { CopyIcon, CheckIcon } from "../lib/icons";

interface Props {
  lines: string[];
  live?: boolean;
}

export function LogViewer({ lines }: Props) {
  const ref = useRef<HTMLDivElement>(null);
  const stickyRef = useRef(true);
  const [copied, setCopied] = useState(false);

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

  const copyAll = async () => {
    try {
      await navigator.clipboard.writeText(lines.join("\n"));
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1500);
    } catch {
      // Clipboard API unavailable — silently ignore.
    }
  };

  return (
    <div className="surface-card overflow-hidden">
      <div className="flex items-center justify-between px-4 py-2 border-b border-white/[0.05] text-[11px]">
        <span className="text-zinc-500 font-mono">stdout / stderr</span>
        <button
          type="button"
          onClick={copyAll}
          disabled={lines.length === 0}
          className={clsx(
            "inline-flex items-center gap-1.5 px-2 py-1 rounded text-zinc-400 hover:text-zinc-100 hover:bg-white/5 transition-colors",
            "disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-transparent"
          )}
          aria-label="Copy logs"
        >
          {copied ? (
            <>
              <CheckIcon size={12} /> Copied
            </>
          ) : (
            <>
              <CopyIcon size={12} /> Copy
            </>
          )}
        </button>
      </div>
      <div
        ref={ref}
        onScroll={onScroll}
        className="font-mono text-xs leading-relaxed text-zinc-200 bg-[var(--surface-0)] p-3 h-96 overflow-y-auto whitespace-pre-wrap break-all"
      >
        {lines.length === 0 ? (
          <span className="text-zinc-600 italic">Waiting for ffmpeg output…</span>
        ) : (
          lines.map((line, idx) => {
            const isError = /\b(Error|failed|invalid|Unable)\b/i.test(line);
            return (
              <div
                key={idx}
                className={clsx(
                  "py-px",
                  isError && "text-rose-300 bg-rose-500/[0.04] -mx-3 px-3 border-l-2 border-rose-500/40"
                )}
              >
                {line}
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}
