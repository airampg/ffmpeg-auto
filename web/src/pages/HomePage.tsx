import { UploadForm } from "../components/UploadForm";
import { JobsList } from "../components/JobsList";
import { AppShell } from "../components/AppShell";

export function HomePage() {
  return (
    <AppShell>
      <div className="space-y-10">
        <section className="space-y-2 max-w-2xl">
          <h1 className="text-3xl font-semibold tracking-tight bg-gradient-to-br from-white via-white to-zinc-400 bg-clip-text text-transparent">
            Convert and segment audio for transcription
          </h1>
          <p className="text-sm text-zinc-400 leading-relaxed">
            Upload an audio or video file, optionally trim a section, and let ffmpeg slice it into chunks
            ready for your transcription pipeline.
          </p>
        </section>

        <section className="space-y-3">
          <SectionHeader title="New job" subtitle="Upload a file to get started" />
          <UploadForm />
        </section>

        <section className="space-y-3">
          <SectionHeader title="Recent jobs" subtitle="Latest 50 runs from the queue" />
          <JobsList />
        </section>
      </div>
    </AppShell>
  );
}

function SectionHeader({ title, subtitle }: { title: string; subtitle?: string }) {
  return (
    <div className="flex items-baseline justify-between gap-3 border-b border-white/[0.06] pb-2">
      <div>
        <h2 className="text-[11px] uppercase tracking-[0.2em] text-zinc-500 font-medium">{title}</h2>
      </div>
      {subtitle && <p className="text-xs text-zinc-500">{subtitle}</p>}
    </div>
  );
}
