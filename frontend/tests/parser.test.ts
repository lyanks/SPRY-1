import { afterEach, describe, expect, it, vi } from "vitest";

import {
  ParseError,
  agendaToText,
  parseAgenda,
  suggestionToForm,
  type ParsedAgenda,
} from "@/lib/parser";

const AGENDA: ParsedAgenda = {
  title: "Pricing sync",
  starts_at: "2026-10-19T10:00:00+03:00",
  duration_minutes: 45,
  items: [
    { topic: "New Pro prices", owner: "Olena", minutes: 15 },
    { topic: "Customer feedback", owner: "Taras", minutes: null },
    { topic: "Annual discount" },
  ],
  action_items: [
    { task: "Compare with competitors", owner: "Taras", due: "2026-10-23" },
  ],
  language: "en",
};

function mockFetch(status: number, body: unknown = {}) {
  return vi.spyOn(globalThis, "fetch").mockResolvedValue({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  } as Response);
}

afterEach(() => vi.restoreAllMocks());

describe("agendaToText", () => {
  it("numbers the items and lists the action items", () => {
    expect(agendaToText(AGENDA)).toBe(
      [
        "1. New Pro prices — Olena, 15 min",
        "2. Customer feedback — Taras",
        "3. Annual discount",
        "",
        "Action items:",
        "- Compare with competitors — Taras, by 2026-10-23",
      ].join("\n"),
    );
  });

  it("is empty when there is nothing to list", () => {
    expect(agendaToText({ items: [], action_items: [], language: "en" })).toBe(
      "",
    );
  });
});

describe("suggestionToForm", () => {
  const current = {
    starts_at: "2026-10-20T09:00",
    ends_at: "2026-10-20T10:30",
  };

  it("fills what the text gave, in Kyiv wall-clock time, and marks it", () => {
    const { values, suggested } = suggestionToForm(AGENDA, current);
    expect(values.title).toBe("Pricing sync");
    expect(values.starts_at).toBe("2026-10-19T10:00");
    expect(values.ends_at).toBe("2026-10-19T10:45");
    expect(values.agenda).toContain("1. New Pro prices");
    expect(suggested).toEqual(["title", "starts_at", "ends_at", "agenda"]);
  });

  it("leaves empty what the text did not say", () => {
    const { values, suggested } = suggestionToForm(
      { items: [{ topic: "Budget" }], action_items: [], language: "en" },
      current,
    );
    expect(Object.keys(values)).toEqual(["agenda"]);
    expect(suggested).toEqual(["agenda"]);
  });

  it("keeps the form's length when only the start is known, and does not mark the end", () => {
    const { values, suggested } = suggestionToForm(
      { ...AGENDA, duration_minutes: null },
      current,
    );
    expect(values.starts_at).toBe("2026-10-19T10:00");
    expect(values.ends_at).toBe("2026-10-19T11:30"); // the form's 90 minutes
    expect(suggested).not.toContain("ends_at");
  });
});

describe("parseAgenda", () => {
  const ok = { agenda: AGENDA, model: "m", prompt_version: "agenda-v1" };

  it("posts the text with today's date, the zone and the token", async () => {
    const spy = mockFetch(200, ok);
    const result = await parseAgenda("Mon 10:00 sync", {
      url: "https://parser.example",
      now: new Date("2026-10-19T08:00:00Z"),
    });
    expect(result.agenda.title).toBe("Pricing sync");
    const [url, init] = spy.mock.calls[0];
    expect(url).toBe("https://parser.example");
    expect(init?.method).toBe("POST");
    expect(JSON.parse(String(init?.body))).toEqual({
      text: "Mon 10:00 sync",
      today: "2026-10-19",
      tz: "Europe/Kyiv",
    });
  });

  it.each([
    [401, "auth"],
    [413, "too_long"],
    [422, "no_agenda"],
    [429, "busy"],
    [503, "busy"],
    [502, "other"],
  ])("maps HTTP %i to %s", async (status, kind) => {
    mockFetch(status);
    await expect(parseAgenda("x", { url: "https://p" })).rejects.toMatchObject({
      kind,
    });
  });

  it("reports a network failure", async () => {
    vi.spyOn(globalThis, "fetch").mockRejectedValue(new TypeError("offline"));
    await expect(parseAgenda("x", { url: "https://p" })).rejects.toBeInstanceOf(
      ParseError,
    );
  });

  it("treats an answer with nothing in it as no agenda", async () => {
    mockFetch(200, {
      ...ok,
      agenda: { items: [], action_items: [], language: "en" },
    });
    await expect(
      parseAgenda("buy milk", { url: "https://p" }),
    ).rejects.toMatchObject({ kind: "no_agenda" });
  });

  it("rejects a response of the wrong shape", async () => {
    mockFetch(200, { nope: true });
    await expect(parseAgenda("x", { url: "https://p" })).rejects.toMatchObject({
      kind: "other",
    });
  });

  it("lets an abort through unchanged", async () => {
    vi.spyOn(globalThis, "fetch").mockRejectedValue(
      new DOMException("aborted", "AbortError"),
    );
    await expect(parseAgenda("x", { url: "https://p" })).rejects.toMatchObject({
      name: "AbortError",
    });
  });
});
