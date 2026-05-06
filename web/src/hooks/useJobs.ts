import { useQuery } from "@tanstack/react-query";
import { listJobs } from "../api/jobs";
import type { JobSummary } from "../api/types";

const ACTIVE: JobSummary["status"][] = ["queued", "running"];

export function useJobs() {
  return useQuery({
    queryKey: ["jobs"],
    queryFn: listJobs,
    refetchInterval: (query) => {
      const data = query.state.data;
      if (Array.isArray(data) && data.some((job) => ACTIVE.includes(job.status))) {
        return 2000;
      }
      return false;
    }
  });
}
