import { Link } from "react-router-dom";
import { useJobs } from "../hooks/useJobs";
import { StatusBadge } from "./StatusBadge";
import { formatDate } from "../lib/format";

export function JobsList() {
  const jobs = useJobs();

  if (jobs.isLoading) return <p className="text-sm text-zinc-500">Loading jobs…</p>;
  if (jobs.error) return <p className="text-sm text-rose-400">Could not load jobs.</p>;
  if (!jobs.data || jobs.data.length === 0) {
    return <p className="text-sm text-zinc-500">No jobs yet. Upload one above.</p>;
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="text-left text-xs uppercase text-zinc-500 border-b border-zinc-800">
            <th className="py-2 pr-4">Job</th>
            <th className="py-2 pr-4">Status</th>
            <th className="py-2 pr-4">Created</th>
            <th className="py-2 pr-4">File</th>
          </tr>
        </thead>
        <tbody>
          {jobs.data.map((job) => (
            <tr key={job.jobId} className="border-b border-zinc-900 hover:bg-zinc-900/50">
              <td className="py-2 pr-4 font-mono text-xs">
                <Link to={`/jobs/${job.jobId}`} className="text-accent hover:underline">
                  {job.jobId.slice(0, 8)}
                </Link>
              </td>
              <td className="py-2 pr-4"><StatusBadge status={job.status} /></td>
              <td className="py-2 pr-4 text-zinc-400">{formatDate(job.createdAt)}</td>
              <td className="py-2 pr-4 truncate max-w-xs">{job.inputFilename}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
