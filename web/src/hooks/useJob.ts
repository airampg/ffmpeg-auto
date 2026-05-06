import { useQuery } from "@tanstack/react-query";
import { getJob } from "../api/jobs";

const ACTIVE = new Set(["queued", "running"]);

export function useJob(jobId: string | undefined) {
  return useQuery({
    queryKey: ["job", jobId],
    queryFn: () => getJob(jobId as string),
    enabled: typeof jobId === "string" && jobId.length > 0,
    refetchInterval: (query) => {
      const status = query.state.data?.status;
      return status && ACTIVE.has(status) ? 2000 : false;
    }
  });
}
