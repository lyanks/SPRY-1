import type { Meeting, WeekInsights } from "@/lib/api";
import { addDays, tzParts, WORK_TZ } from "@/lib/time";

/**
 * A made-up week for people who are not signed in: it shows what Spry does
 * without touching anyone's data, and is rebuilt around the current week so it
 * never looks stale. Nothing here comes from, or goes to, the API.
 */

/** The instant for a wall-clock time ("2026-10-07", 10, 30) in the working timezone. */
function at(day: string, hour: number, minute = 0): string {
  const [y, m, d] = day.split("-").map(Number);
  const asIfUtc = Date.UTC(y, m - 1, d, hour, minute);
  // What the zone's clock reads at that instant tells us its offset from UTC.
  const p = tzParts(new Date(asIfUtc));
  const shown = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute);
  return new Date(asIfUtc - (shown - asIfUtc)).toISOString();
}

type Seed = {
  day: number;
  from: [number, number];
  to: [number, number];
  title: string;
  people: number;
  kind: Meeting["kind"];
  agenda: string | null;
};

const SEEDS: Seed[] = [
  {
    day: 0,
    from: [10, 0],
    to: [10, 30],
    title: "Weekly planning",
    people: 6,
    kind: "meeting",
    agenda: "Priorities, blockers",
  },
  {
    day: 0,
    from: [13, 0],
    to: [15, 0],
    title: "Deep work: roadmap draft",
    people: 1,
    kind: "focus",
    agenda: null,
  },
  {
    day: 1,
    from: [9, 30],
    to: [10, 15],
    title: "Design review",
    people: 4,
    kind: "meeting",
    agenda: null,
  },
  {
    day: 1,
    from: [11, 0],
    to: [12, 0],
    title: "Customer call",
    people: 3,
    kind: "meeting",
    agenda: "Renewal questions",
  },
  {
    day: 2,
    from: [10, 0],
    to: [12, 0],
    title: "Deep work: spec writing",
    people: 1,
    kind: "focus",
    agenda: null,
  },
  {
    day: 2,
    from: [14, 0],
    to: [15, 0],
    title: "Sprint retro",
    people: 8,
    kind: "meeting",
    agenda: null,
  },
  {
    day: 3,
    from: [9, 0],
    to: [9, 15],
    title: "Stand-up",
    people: 7,
    kind: "meeting",
    agenda: "Yesterday, today, blockers",
  },
  {
    day: 3,
    from: [12, 30],
    to: [13, 15],
    title: "Lunch with the team",
    people: 5,
    kind: "other",
    agenda: null,
  },
  {
    day: 3,
    from: [15, 0],
    to: [16, 0],
    title: "Hiring sync",
    people: 3,
    kind: "meeting",
    agenda: null,
  },
  {
    day: 4,
    from: [10, 30],
    to: [11, 30],
    title: "Demo to stakeholders",
    people: 9,
    kind: "meeting",
    agenda: "Demo script",
  },
  {
    day: 4,
    from: [13, 0],
    to: [15, 30],
    title: "Deep work: release notes",
    people: 1,
    kind: "focus",
    agenda: null,
  },
];

export function demoMeetings(weekStart: string): Meeting[] {
  return SEEDS.map((seed, i) => {
    const day = addDays(weekStart, seed.day);
    return {
      id: -(i + 1), // negative: can never clash with a real meeting
      title: seed.title,
      starts_at: at(day, ...seed.from),
      ends_at: at(day, ...seed.to),
      attendee_count: seed.people,
      kind: seed.kind,
      agenda: seed.agenda,
      has_agenda: Boolean(seed.agenda),
    };
  });
}

export function demoInsights(weekStart: string): WeekInsights {
  const minutes = (m: Meeting) =>
    (new Date(m.ends_at).getTime() - new Date(m.starts_at).getTime()) / 60000;
  const meetings = demoMeetings(weekStart).filter((m) => m.kind === "meeting");
  const total = meetings.reduce((sum, m) => sum + minutes(m), 0);
  const metric = (value: number, previous: number) => ({
    value,
    previous,
    change_pct: Math.round(((value - previous) / previous) * 1000) / 10,
  });
  return {
    week_start: weekStart,
    week_end: addDays(weekStart, 6),
    timezone: WORK_TZ,
    meeting_minutes: metric(total, total + 150),
    meeting_count: metric(meetings.length, meetings.length + 2),
    deep_work_minutes: metric(1260, 900),
  };
}
