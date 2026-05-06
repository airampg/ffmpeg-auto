import { outputDownloadURL, zipDownloadURL } from "../api/jobs";
import type { JobOutput } from "../api/types";
import { formatBytes } from "../lib/format";

export function OutputsList({ jobId, outputs }: { jobId: string; outputs: JobOutput[] }) {
  if (outputs.length === 0) {
    return <p className="text-sm text-zinc-500">No outputs yet.</p>;
  }
  return (
    <div className="space-y-3">
      <div>
        <a
          className="inline-block bg-accent text-zinc-900 font-medium px-3 py-1.5 rounded text-sm hover:opacity-90"
          href={zipDownloadURL(jobId)}
          download={`${jobId}.zip`}
        >
          Download all as zip
        </a>
      </div>
      <ul className="space-y-1">
        {outputs.map((output) => (
          <li key={output.name} className="flex items-center justify-between border border-zinc-800 rounded px-3 py-2 text-sm">
            <span className="font-mono">{output.name}</span>
            <span className="flex items-center gap-3">
              <span className="text-xs text-zinc-500">{formatBytes(output.sizeBytes)}</span>
              <a
                className="text-accent hover:underline"
                href={outputDownloadURL(jobId, output.name)}
                download
              >
                Download
              </a>
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}
