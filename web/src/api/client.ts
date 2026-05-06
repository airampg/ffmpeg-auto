import type { ApiErrorPayload } from "./types";

export class ApiError extends Error {
  public readonly code: string;
  public readonly status: number;
  public readonly payload: ApiErrorPayload | null;

  constructor(code: string, message: string, status: number, payload: ApiErrorPayload | null = null) {
    super(message);
    this.code = code;
    this.status = status;
    this.payload = payload;
  }
}

async function parseResponse<T>(response: Response): Promise<T> {
  if (response.status === 204) {
    return undefined as T;
  }
  const text = await response.text();
  let body: unknown = null;
  if (text) {
    try {
      body = JSON.parse(text);
    } catch {
      body = null;
    }
  }
  if (!response.ok) {
    const payload = (body as ApiErrorPayload | null) ?? null;
    throw new ApiError(
      payload?.code ?? "HTTP_ERROR",
      payload?.message ?? `HTTP ${response.status}`,
      response.status,
      payload
    );
  }
  return body as T;
}

export async function apiGet<T>(path: string): Promise<T> {
  const response = await fetch(path, { method: "GET" });
  return parseResponse<T>(response);
}

export async function apiDelete(path: string): Promise<void> {
  const response = await fetch(path, { method: "DELETE" });
  await parseResponse<void>(response);
}
