import { apiGet } from "./client";
import type { Capabilities } from "./types";

export const getCapabilities = (): Promise<Capabilities> => apiGet<Capabilities>("/api/v1/capabilities");
