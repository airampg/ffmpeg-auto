import { UploadForm } from "../components/UploadForm";
import { JobsList } from "../components/JobsList";

export function HomePage() {
  return (
    <div className="max-w-4xl mx-auto p-6 space-y-8">
      <header className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold">FFmpegAuto</h1>
          <p className="text-sm text-zinc-400">Segment audio for transcription pipelines.</p>
        </div>
        <div className="text-xs text-zinc-500 font-mono">v0.1 · web</div>
      </header>

      <section>
        <h2 className="text-sm uppercase tracking-wide text-zinc-400 mb-3">New job</h2>
        <UploadForm />
      </section>

      <section>
        <h2 className="text-sm uppercase tracking-wide text-zinc-400 mb-3">Recent jobs</h2>
        <JobsList />
      </section>
    </div>
  );
}
