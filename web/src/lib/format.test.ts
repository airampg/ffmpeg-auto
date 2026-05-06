import { describe, it, expect } from "vitest";
import { formatBytes, formatSeconds, formatSecondsPrecise, parseTimecode } from "./format";

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

describe("formatSecondsPrecise", () => {
  it("formats with millisecond precision", () => {
    expect(formatSecondsPrecise(0)).toBe("00:00:00.000");
    expect(formatSecondsPrecise(12.5)).toBe("00:00:12.500");
    expect(formatSecondsPrecise(65.123)).toBe("00:01:05.123");
    expect(formatSecondsPrecise(3661.001)).toBe("01:01:01.001");
  });

  it("clamps negatives to zero", () => {
    expect(formatSecondsPrecise(-1)).toBe("00:00:00.000");
  });

  it("returns zero pad for null/undefined/Infinity", () => {
    expect(formatSecondsPrecise(null)).toBe("00:00:00.000");
    expect(formatSecondsPrecise(undefined)).toBe("00:00:00.000");
    expect(formatSecondsPrecise(Infinity)).toBe("00:00:00.000");
  });
});

describe("parseTimecode", () => {
  it("parses plain seconds", () => {
    expect(parseTimecode("12")).toBe(12);
    expect(parseTimecode("12.5")).toBe(12.5);
  });

  it("parses MM:SS", () => {
    expect(parseTimecode("01:30")).toBe(90);
    expect(parseTimecode("00:45.250")).toBe(45.25);
  });

  it("parses HH:MM:SS.mmm", () => {
    expect(parseTimecode("01:01:01")).toBe(3661);
    expect(parseTimecode("01:01:01.500")).toBe(3661.5);
  });

  it("ignores surrounding whitespace", () => {
    expect(parseTimecode("  00:30  ")).toBe(30);
  });

  it("returns null on invalid input", () => {
    expect(parseTimecode("")).toBeNull();
    expect(parseTimecode("nope")).toBeNull();
    expect(parseTimecode("01:02:03:04")).toBeNull();
    expect(parseTimecode("-5")).toBeNull();
  });
});
