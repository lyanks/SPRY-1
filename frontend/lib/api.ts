import { z } from "zod";

export function apiBaseUrl(): string {
  if (typeof window === "undefined") {
    return process.env.INTERNAL_API_URL ?? "http://backend:8000";
  }
  return process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000";
}

export class ApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

async function request<T>(
  path: string,
  schema: z.ZodType<T>,
  init?: RequestInit,
): Promise<T> {
  let response: Response;
  try {
    response = await fetch(`${apiBaseUrl()}${path}`, {
      ...init,
      cache: "no-store",
      headers: {
        "Content-Type": "application/json",
        ...(init?.headers ?? {}),
      },
    });
  } catch {
    throw new ApiError(0, "Could not reach the API");
  }

  if (!response.ok) {
    const detail = await response
      .json()
      .then((body) => (typeof body?.detail === "string" ? body.detail : null))
      .catch(() => null);
    throw new ApiError(
      response.status,
      detail ?? `Request failed (${response.status})`,
    );
  }

  if (response.status === 204) {
    return schema.parse(undefined);
  }
  return schema.parse(await response.json());
}

/* --- schemas mirroring PROJECT.md section 3 --- */

export const kindSchema = z.enum(["meeting", "focus", "other"]);

export const meetingSchema = z.object({
  id: z.number(),
  title: z.string(),
  starts_at: z.string(),
  ends_at: z.string(),
  attendee_count: z.number().int(),
  kind: kindSchema,
  agenda: z.string().nullable(),
  has_agenda: z.boolean(),
});

export const meetingListSchema = z.array(meetingSchema);

export const meetingInputSchema = z
  .object({
    title: z
      .string()
      .min(1, "Add a title")
      .max(255, "Keep the title under 255 characters"),
    starts_at: z.string().min(1, "Pick a start time"),
    ends_at: z.string().min(1, "Pick an end time"),
    attendee_count: z.number().int().min(1, "At least 1 attendee").max(1000),
    agenda: z.string().max(10000, "Keep the agenda under 10 000 characters"),
  })
  .refine((v) => !v.starts_at || !v.ends_at || v.ends_at > v.starts_at, {
    path: ["ends_at"],
    message: "End time must be after the start",
  });

const metricSchema = z.object({
  value: z.number(),
  previous: z.number(),
  change_pct: z.number().nullable(),
});

export const weekInsightsSchema = z.object({
  week_start: z.string(),
  week_end: z.string(),
  timezone: z.string(),
  meeting_minutes: metricSchema,
  meeting_count: metricSchema,
  deep_work_minutes: metricSchema,
});

export const slotProposalSchema = z.object({
  slots: z.array(
    z.object({
      starts_at: z.string(),
      ends_at: z.string(),
      minutes: z.number(),
    }),
  ),
  total_minutes: z.number(),
});

export const agendaReadinessSchema = z.object({
  window_days: z.number(),
  upcoming: z.number(),
  without_agenda: z.number(),
  without_agenda_pct: z.number(),
  meetings: meetingListSchema,
});

export const healthSchema = z.object({ status: z.string() });

export type Meeting = z.infer<typeof meetingSchema>;
export type MeetingKind = z.infer<typeof kindSchema>;
export type MeetingInput = z.infer<typeof meetingInputSchema>;
export type Metric = z.infer<typeof metricSchema>;
export type WeekInsights = z.infer<typeof weekInsightsSchema>;
export type Slot = z.infer<typeof slotProposalSchema>["slots"][number];
export type SlotProposal = z.infer<typeof slotProposalSchema>;
export type AgendaReadiness = z.infer<typeof agendaReadinessSchema>;

/** Body sent to the API: instants as ISO strings, agenda null when blank. */
export type MeetingPayload = {
  title: string;
  starts_at: string;
  ends_at: string;
  attendee_count: number;
  agenda: string | null;
};

/* --- endpoints --- */

const json = (method: string, body: unknown): RequestInit => ({
  method,
  body: JSON.stringify(body),
});

export const api = {
  health: () => request("/health", healthSchema),

  listMeetings: (range?: { starts_after?: string; starts_before?: string }) => {
    const query = new URLSearchParams();
    if (range?.starts_after) query.set("starts_after", range.starts_after);
    if (range?.starts_before) query.set("starts_before", range.starts_before);
    const qs = query.toString();
    return request(`/api/meetings${qs ? `?${qs}` : ""}`, meetingListSchema);
  },

  createMeeting: (payload: MeetingPayload) =>
    request("/api/meetings", meetingSchema, json("POST", payload)),

  updateMeeting: (id: number, payload: Partial<MeetingPayload>) =>
    request(`/api/meetings/${id}`, meetingSchema, json("PATCH", payload)),

  deleteMeeting: (id: number) =>
    request(`/api/meetings/${id}`, z.undefined(), { method: "DELETE" }),

  weekInsights: (weekOf: string) =>
    request(`/api/insights/week?week_of=${weekOf}`, weekInsightsSchema),

  agendaReadiness: () =>
    request("/api/agenda/readiness", agendaReadinessSchema),

  deepWorkSlots: () => request("/api/deep-work/slots", slotProposalSchema),

  reserveDeepWork: (slot: { starts_at: string; ends_at: string }) =>
    request("/api/deep-work/reserve", meetingSchema, json("POST", slot)),
};
