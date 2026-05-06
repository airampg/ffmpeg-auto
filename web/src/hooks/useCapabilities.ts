import { useQuery } from "@tanstack/react-query";
import { getCapabilities } from "../api/capabilities";

export function useCapabilities() {
  return useQuery({
    queryKey: ["capabilities"],
    queryFn: getCapabilities,
    staleTime: Infinity,
    gcTime: 60 * 60 * 1000
  });
}
