import { ApiError, apiGet, apiDelete } from "./client";
import type {
  JobDetail,
  JobsListResponse,
  JobSummary,
  JobCreatedResponse,
  JobSubmitSettings,
  ApiErrorPayload
} from "./types";

export const getJob = (id: string): Promise<JobDetail> => apiGet<JobDetail>(`/api/v1/jobs/${id}`);

export const listJobs = async (): Promise<JobSummary[]> =>
  (await apiGet<JobsListResponse>("/api/v1/jobs")).jobs;

export const deleteJob = (id: string): Promise<void> => apiDelete(`/api/v1/jobs/${id}`);

export const outputDownloadURL = (id: string, name: string): string =>
  `/api/v1/jobs/${id}/outputs/${encodeURIComponent(name)}`;

export const zipDownloadURL = (id: string): string =>
  `/api/v1/jobs/${id}/outputs.zip`;

export interface CreateJobOptions {
  file: File;
  settings: JobSubmitSettings;
  onUploadProgress?: (fraction: number) => void;
}

export function createJob(opts: CreateJobOptions): Promise<JobCreatedResponse> {
  const fd = new FormData();
  const settingsBlob = new Blob([JSON.stringify(opts.settings)], { type: "application/json" });
  fd.append("settings", settingsBlob);
  fd.append("file", opts.file);

  return new Promise<JobCreatedResponse>((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open("POST", "/api/v1/jobs");
    xhr.upload.onprogress = (event) => {
      if (event.lengthComputable && opts.onUploadProgress) {
        opts.onUploadProgress(event.loaded / event.total);
      }
    };
    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        try {
          resolve(JSON.parse(xhr.responseText));
        } catch (error) {
          reject(new ApiError("INVALID_RESPONSE", "Failed to parse server response.", xhr.status));
        }
      } else {
        let payload: ApiErrorPayload | null = null;
        try {
          payload = JSON.parse(xhr.responseText);
        } catch {
          payload = null;
        }
        reject(new ApiError(
          payload?.code ?? "HTTP_ERROR",
          payload?.message ?? `HTTP ${xhr.status}`,
          xhr.status,
          payload
        ));
      }
    };
    xhr.onerror = () => reject(new ApiError("NETWORK_ERROR", "Network error during upload.", 0));
    xhr.onabort = () => reject(new ApiError("ABORTED", "Upload aborted.", 0));
    xhr.send(fd);
  });
}
