import { Link } from "react-router-dom";
import { ScissorsIcon } from "../lib/icons";

interface Props {
  children: React.ReactNode;
}

export function AppShell({ children }: Props) {
  return (
    <div className="min-h-full">
      <header className="sticky top-0 z-30 backdrop-blur-md bg-[rgba(8,8,11,0.75)] border-b border-white/[0.06]">
        <div className="max-w-6xl mx-auto px-6 h-14 flex items-center justify-between">
          <Link to="/" className="flex items-center gap-2.5 group">
            <div className="grid place-items-center w-8 h-8 rounded-lg bg-gradient-to-br from-[var(--color-accent)] to-[var(--color-accent-strong)] shadow-[0_4px_14px_-4px_var(--color-accent-glow)]">
              <ScissorsIcon size={16} className="text-[#06201d]" />
            </div>
            <div className="leading-tight">
              <div className="text-sm font-semibold tracking-tight">FFmpegAuto</div>
              <div className="text-[10px] uppercase tracking-[0.18em] text-zinc-500">Audio Segmenter</div>
            </div>
          </Link>
          <div className="flex items-center gap-3 text-xs text-zinc-500 font-mono">
            <span className="hidden sm:inline">v0.1</span>
            <a
              href="https://github.com"
              target="_blank"
              rel="noreferrer"
              className="text-zinc-500 hover:text-zinc-300 transition-colors"
              aria-label="Source"
            >
              web
            </a>
          </div>
        </div>
      </header>
      <main className="max-w-6xl mx-auto px-6 py-8">{children}</main>
    </div>
  );
}
