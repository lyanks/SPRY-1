import { afterEach, describe, expect, it, vi } from "vitest";

import { api } from "@/lib/api";

import { makeMeeting } from "./utils";

function mockFetch(body: unknown, init: { status?: number } = {}) {
  const status = init.status ?? 200;
  return vi.spyOn(globalThis, "fetch").mockResolvedValue({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  } as Response);
}

afterEach(() => vi.restoreAllMocks());

describe("meetings api", () => {
  it("parses the meeting list", async () => {
    const meetings = [makeMeeting()];
    mockFetch(meetings);
    await expect(api.listMeetings()).resolves.toEqual(meetings);
  });

  it("sends the range as query parameters", async () => {
    const spy = mockFetch([]);
    await api.listMeetings({ starts_after: "2026-10-01T00:00:00Z" });
    expect(String(spy.mock.calls[0][0])).toContain(
      "/api/meetings?starts_after=2026-10-01T00%3A00%3A00Z",
    );
  });

  it("creates a meeting", async () => {
    const payload = {
      title: "Sprint retro",
      starts_at: "2026-10-01T15:00:00Z",
      ends_at: "2026-10-01T16:00:00Z",
      attendee_count: 5,
      agenda: null,
    };
    const spy = mockFetch(makeMeeting({ id: 2, title: payload.title }));
    const result = await api.createMeeting(payload);
    expect(result.id).toBe(2);
    expect(spy.mock.calls[0][1]).toMatchObject({ method: "POST" });
  });

  it("edits with PATCH", async () => {
    const spy = mockFetch(makeMeeting({ title: "Renamed" }));
    await api.updateMeeting(1, { title: "Renamed" });
    expect(String(spy.mock.calls[0][0])).toContain("/api/meetings/1");
    expect(spy.mock.calls[0][1]).toMatchObject({ method: "PATCH" });
  });

  it("deletes and accepts the empty 204 response", async () => {
    const spy = mockFetch(undefined, { status: 204 });
    await expect(api.deleteMeeting(7)).resolves.toBeUndefined();
    expect(String(spy.mock.calls[0][0])).toContain("/api/meetings/7");
    expect(spy.mock.calls[0][1]).toMatchObject({ method: "DELETE" });
  });

  it("raises ApiError with the server's detail", async () => {
    mockFetch({ detail: "Meeting not found" }, { status: 404 });
    await expect(api.deleteMeeting(9)).rejects.toMatchObject({
      status: 404,
      message: "Meeting not found",
    });
  });

  it("parses week insights", async () => {
    const metric = { value: 60, previous: 240, change_pct: -75 };
    mockFetch({
      week_start: "2026-10-05",
      week_end: "2026-10-11",
      timezone: "Europe/Kyiv",
      meeting_minutes: metric,
      meeting_count: { value: 1, previous: 2, change_pct: -50 },
      deep_work_minutes: { value: 2640, previous: 2460, change_pct: 7.3 },
    });
    const result = await api.weekInsights("2026-10-05");
    expect(result.meeting_minutes).toEqual(metric);
  });
});
