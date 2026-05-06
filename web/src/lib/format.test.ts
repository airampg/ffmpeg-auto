import { describe, it, expect } from "vitest";
import { formatBytes, formatSeconds } from "./format";

describe("formatBytes", () => {
  it("formats small values", () => {
    expect(formatBytes(0)).toBe("0 B");
    expect(formatBytes(512)).toBe("512 B");
  });

  it("formats kilobytes", () => {
    expect(formatBytes(1024)).toBe("1.0 KB");
    expect(formatBytes(2048)).toBe("2.0 KB");
  });

  it("formats megabytes with one decimal under 10", () => {
    expect(formatBytes(1024 * 1024)).toBe("1.0 MB");
    expect(formatBytes(1024 * 1024 * 12)).toBe("12 MB");
  });

  it("returns dash for negative", () => {
    expect(formatBytes(-1)).toBe("—");
  });
});

describe("formatSeconds", () => {
  it("formats minutes and seconds", () => {
    expect(formatSeconds(0)).toBe("0:00");
    expect(formatSeconds(65)).toBe("1:05");
    expect(formatSeconds(125)).toBe("2:05");
  });

  it("formats hours when long", () => {
    expect(formatSeconds(3661)).toBe("1:01:01");
  });

  it("returns dash for null", () => {
    expect(formatSeconds(null)).toBe("—");
    expect(formatSeconds(undefined)).toBe("—");
  });
});
