import { z } from "zod";

import { readAccessToken } from "@/lib/auth-config";
import type { MeetingInput } from "@/lib/api";
import { WORK_TZ, fromInputValue, todayKey, toInputValue } from "@/lib/time";

/**
 * Paste an agenda (Lab 6). The parser is a separate Lambda function with its
 * own URL, compiled in like the API's. It only suggests: nothing it returns is
 * saved until the person presses Save, and saving goes through the normal API.
 * Without the URL (local dev, or before `make deploy-ai`) the feature is hidden.
 */
export const parserUrl = (process.env.NEXT_PUBLIC_PARSER_URL ?? "").replace(
  /\/$/,
  "",
);
export const parserEnabled = Boolean(parserUrl);

export const MAX_PASTE_CHARS = 10_000;

const parsedAgendaSchema = z.object({
  title: z.string().nullable().optional(),
  starts_at: z.string().nullable().optional(),
  duration_minutes: z.number().nullable().optional(),
  items: z.array(
    z.object({
      topic: z.string(),
      owner: z.string().nullable().optional(),
      minutes: z.number().nullable().optional(),
    }),
  ),
  action_items: z
    .array(
      z.object({
        task: z.string(),
        owner: z.string().nullable().optional(),
        due: z.string().nullable().optional(),
      }),
    )
    .default([]),
  language: z.string(),
});

export const parseResponseSchema = z.object({
  agenda: parsedAgendaSchema,
  model: z.string(),
  prompt_version: z.string(),
});

export type ParsedAgenda = z.infer<typeof parsedAgendaSchema>;
export type ParseResponse = z.infer<typeof parseResponseSchema>;

export type ParseErrorKind =
  "auth" | "too_long" | "no_agenda" | "busy" | "network" | "other";

const MESSAGES: Record<ParseErrorKind, string> = {
  auth: "Your sign-in has expired. Sign in again to parse an agenda.",
  too_long: `That text is too long. Paste at most ${MAX_PASTE_CHARS.toLocaleString("en")} characters.`,
  no_agenda:
    "Couldn’t find an agenda in that text. You can still type it in yourself.",
  busy: "The AI service is busy right now. Try again in a moment.",
  network: "Couldn’t reach the parser. Check your connection and try again.",
  other: "The parser failed. You can still type the agenda in yourself.",
};

export class ParseError extends Error {
  constructor(readonly kind: ParseErrorKind) {
    super(MESSAGES[kind]);
    this.name = "ParseError";
  }
}

const kindForStatus = (status: number): ParseErrorKind =>
  status === 401
    ? "auth"
    : status === 413
      ? "too_long"
      : status === 422
        ? "no_agenda"
        : status === 429 || status === 503
          ? "busy"
          : "other";

/** Send the pasted text to the parser. Aborting `signal` cancels the request. */
export async function parseAgenda(
  text: string,
  options: { signal?: AbortSignal; url?: string; now?: Date } = {},
): Promise<ParseResponse> {
  const url = options.url ?? parserUrl;
  const token = readAccessToken();
  let response: Response;
  try {
    response = await fetch(url, {
      method: "POST",
      signal: options.signal,
      headers: {
        "Content-Type": "application/json",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      // "Monday" is the person's Monday, and the function runs in UTC, so the
      // browser says which day it is and in which zone.
      body: JSON.stringify({
        text,
        today: todayKey(options.now),
        tz: WORK_TZ,
      }),
    });
  } catch (err) {
    if (err instanceof DOMException && err.name === "AbortError") throw err;
    throw new ParseError("network");
  }
  if (!response.ok) throw new ParseError(kindForStatus(response.status));

  const parsed = parseResponseSchema.safeParse(
    await response.json().catch(() => null),
  );
  if (!parsed.success) throw new ParseError("other");
  const agenda = parsed.data.agenda;
  if (
    agenda.items.length === 0 &&
    agenda.action_items.length === 0 &&
    !agenda.title &&
    !agenda.starts_at
  ) {
    throw new ParseError("no_agenda");
  }
  return parsed.data;
}

/** The agenda as the plain text the agenda field holds today. */
export function agendaToText(agenda: ParsedAgenda): string {
  const lines = agenda.items.map((item, i) => {
    const extra = [item.owner, item.minutes ? `${item.minutes} min` : null]
      .filter(Boolean)
      .join(", ");
    return `${i + 1}. ${item.topic}${extra ? ` — ${extra}` : ""}`;
  });
  if (agenda.action_items.length > 0) {
    if (lines.length > 0) lines.push("");
    lines.push("Action items:");
    for (const a of agenda.action_items) {
      const extra = [a.owner, a.due ? `by ${a.due}` : null]
        .filter(Boolean)
        .join(", ");
      lines.push(`- ${a.task}${extra ? ` — ${extra}` : ""}`);
    }
  }
  return lines.join("\n");
}

export type SuggestedField = "title" | "starts_at" | "ends_at" | "agenda";

/**
 * What to put in the form. Only fields the text actually gave are returned,
 * and `suggested` lists the ones to mark with a badge. Empty stays empty.
 */
export function suggestionToForm(
  agenda: ParsedAgenda,
  current: Pick<MeetingInput, "starts_at" | "ends_at">,
): { values: Partial<MeetingInput>; suggested: SuggestedField[] } {
  const values: Partial<MeetingInput> = {};
  const suggested: SuggestedField[] = [];

  if (agenda.title) {
    values.title = agenda.title;
    suggested.push("title");
  }

  if (agenda.starts_at) {
    const startsAt = toInputValue(agenda.starts_at);
    values.starts_at = startsAt;
    suggested.push("starts_at");

    // The end follows the start: the stated duration if there is one,
    // otherwise whatever length the form already had (not marked: the text
    // did not say it).
    const keptMinutes = Math.max(
      15,
      Math.round(
        (Date.parse(fromInputValue(current.ends_at)) -
          Date.parse(fromInputValue(current.starts_at))) /
          60_000,
      ) || 60,
    );
    const minutes = agenda.duration_minutes ?? keptMinutes;
    values.ends_at = toInputValue(
      new Date(Date.parse(agenda.starts_at) + minutes * 60_000).toISOString(),
    );
    if (agenda.duration_minutes) suggested.push("ends_at");
  }

  const text = agendaToText(agenda);
  if (text) {
    values.agenda = text;
    suggested.push("agenda");
  }
  return { values, suggested };
}
