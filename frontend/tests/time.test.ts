import { describe, expect, it } from "vitest";

import {
  addDays,
  dayKey,
  formatDuration,
  formatTime,
  fromInputValue,
  hoursOf,
  mondayOf,
  toInputValue,
} from "@/lib/time";

describe("working timezone", () => {
  it("shows Kyiv wall-clock time (UTC+3 in October)", () => {
    expect(formatTime("2026-10-07T07:00:00Z")).toBe("10:00");
    expect(dayKey("2026-10-07T22:30:00Z")).toBe("2026-10-08"); // already after midnight in Kyiv
  });

  it("round-trips datetime-local values", () => {
    const iso = "2026-10-07T07:30:00.000Z";
    expect(toInputValue(iso)).toBe("2026-10-07T10:30");
    expect(fromInputValue("2026-10-07T10:30")).toBe(iso);
  });

  it("handles winter time (UTC+2)", () => {
    expect(fromInputValue("2026-12-01T09:00")).toBe("2026-12-01T07:00:00.000Z");
  });
});

describe("week maths", () => {
  it("finds the Monday of a week", () => {
    expect(mondayOf("2026-10-08")).toBe("2026-10-05");
    expect(mondayOf("2026-10-05")).toBe("2026-10-05");
    expect(mondayOf("2026-10-11")).toBe("2026-10-05");
  });

  it("adds days across month ends", () => {
    expect(addDays("2026-10-30", 3)).toBe("2026-11-02");
    expect(addDays("2026-10-05", -7)).toBe("2026-09-28");
  });
});

describe("formatting", () => {
  it("formats durations", () => {
    expect(formatDuration(45)).toBe("45 min");
    expect(formatDuration(120)).toBe("2 h");
    expect(formatDuration(150)).toBe("2 h 30 min");
  });

  it("formats hours", () => {
    expect(hoursOf(120)).toBe("2");
    expect(hoursOf(90)).toBe("1.5");
  });
});
