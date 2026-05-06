export function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes < 0) return "—";
  const units = ["B", "KB", "MB", "GB", "TB"];
  let value = bytes;
  let i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  return `${value.toFixed(value < 10 && i > 0 ? 1 : 0)} ${units[i]}`;
}

export function formatSeconds(seconds: number | null | undefined): string {
  if (seconds == null || !Number.isFinite(seconds)) return "—";
  const total = Math.max(0, Math.floor(seconds));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  return h > 0
    ? `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`
    : `${m}:${String(s).padStart(2, "0")}`;
}

export function formatDate(iso: string | null | undefined): string {
  if (!iso) return "—";
  try {
    return new Date(iso).toLocaleString();
  } catch {
    return iso;
  }
}

/**
 * Formats seconds as `HH:MM:SS.mmm`. Used by the trim editor where sub-second
 * precision matters for the user.
 */
export function formatSecondsPrecise(seconds: number | null | undefined): string {
  if (seconds == null || !Number.isFinite(seconds)) return "00:00:00.000";
  const clamped = Math.max(0, seconds);
  const totalMs = Math.round(clamped * 1000);
  const ms = totalMs % 1000;
  const totalS = Math.floor(totalMs / 1000);
  const h = Math.floor(totalS / 3600);
  const m = Math.floor((totalS % 3600) / 60);
  const s = totalS % 60;
  return (
    `${String(h).padStart(2, "0")}:` +
    `${String(m).padStart(2, "0")}:` +
    `${String(s).padStart(2, "0")}.` +
    `${String(ms).padStart(3, "0")}`
  );
}

/**
 * Parses a timecode string in any of these forms into seconds:
 *   `SS`, `SS.mmm`, `MM:SS`, `MM:SS.mmm`, `HH:MM:SS`, `HH:MM:SS.mmm`.
 * Returns `null` if the input is not parseable.
 */
export function parseTimecode(input: string): number | null {
  const trimmed = input.trim();
  if (trimmed === "") return null;
  const parts = trimmed.split(":");
  if (parts.length === 0 || parts.length > 3) return null;
  const numbers = parts.map((p) => Number(p));
  if (numbers.some((n) => !Number.isFinite(n) || n < 0)) return null;
  let seconds: number;
  if (numbers.length === 1) {
    seconds = numbers[0];
  } else if (numbers.length === 2) {
    seconds = numbers[0] * 60 + numbers[1];
  } else {
    seconds = numbers[0] * 3600 + numbers[1] * 60 + numbers[2];
  }
  return Number.isFinite(seconds) ? seconds : null;
}
