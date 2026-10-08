/**
 * Dates in Spry are shown in the working timezone, the same one the backend uses to
 * cut weeks (WORK_TIMEZONE). Everything here is plain Intl, no date library.
 */
export const WORK_TZ = "Europe/Kyiv";
export const DAY_START_HOUR = 8;
export const DAY_END_HOUR = 19;

const partsFormat = new Intl.DateTimeFormat("en-GB", {
  timeZone: WORK_TZ,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  hourCycle: "h23",
});

export type Parts = {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
};

export function tzParts(value: string | Date): Parts {
  const out: Record<string, number> = {};
  for (const p of partsFormat.formatToParts(new Date(value))) {
    if (p.type !== "literal") out[p.type] = Number(p.value);
  }
  return out as Parts;
}

const pad = (n: number) => String(n).padStart(2, "0");

/** "2026-10-07" for the calendar day an instant falls on in the working timezone. */
export function dayKey(value: string | Date): string {
  const p = tzParts(value);
  return `${p.year}-${pad(p.month)}-${pad(p.day)}`;
}

/** Add days to a "YYYY-MM-DD" key. Pure calendar arithmetic, no timezone involved. */
export function addDays(key: string, n: number): string {
  const d = new Date(`${key}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

/** Monday of the ISO week containing the key. */
export function mondayOf(key: string): string {
  const weekday = (new Date(`${key}T00:00:00Z`).getUTCDay() + 6) % 7; // Monday = 0
  return addDays(key, -weekday);
}

export function todayKey(now: Date = new Date()): string {
  return dayKey(now);
}

export function weekDays(weekStart: string): string[] {
  return Array.from({ length: 7 }, (_, i) => addDays(weekStart, i));
}

/** Meetings starting between these bounds can touch the week; the API filters on start time. */
export function weekFetchRange(weekStart: string) {
  return {
    starts_after: new Date(`${addDays(weekStart, -2)}T00:00:00Z`).toISOString(),
    starts_before: new Date(`${addDays(weekStart, 9)}T00:00:00Z`).toISOString(),
  };
}

/** Minutes since local midnight, in the working timezone. */
export function minuteOfDay(value: string | Date): number {
  const p = tzParts(value);
  return p.hour * 60 + p.minute;
}

export function formatTime(value: string | Date): string {
  const p = tzParts(value);
  return `${pad(p.hour)}:${pad(p.minute)}`;
}

export function formatDayLong(key: string): string {
  return new Intl.DateTimeFormat("en-GB", {
    timeZone: "UTC",
    weekday: "short",
    day: "numeric",
    month: "short",
  }).format(new Date(`${key}T00:00:00Z`));
}

export function formatMonthYear(key: string): string {
  return new Intl.DateTimeFormat("en-GB", {
    timeZone: "UTC",
    month: "long",
    year: "numeric",
  }).format(new Date(`${key}T00:00:00Z`));
}

export function formatWeekRange(weekStart: string): string {
  const fmt = (key: string, withYear: boolean) =>
    new Intl.DateTimeFormat("en-GB", {
      timeZone: "UTC",
      day: "numeric",
      month: "short",
      ...(withYear ? { year: "numeric" } : {}),
    }).format(new Date(`${key}T00:00:00Z`));
  return `${fmt(weekStart, false)} – ${fmt(addDays(weekStart, 6), true)}`;
}

export function formatDuration(minutes: number): string {
  const m = Math.round(minutes);
  const h = Math.floor(m / 60);
  const rest = m % 60;
  if (h === 0) return `${rest} min`;
  return rest === 0 ? `${h} h` : `${h} h ${rest} min`;
}

export function hoursOf(minutes: number): string {
  const h = minutes / 60;
  return Number.isInteger(h) ? String(h) : h.toFixed(1);
}

/** "2026-10-07T09:30" for a datetime-local input, showing the working timezone's wall clock. */
export function toInputValue(iso: string): string {
  const p = tzParts(iso);
  return `${p.year}-${pad(p.month)}-${pad(p.day)}T${pad(p.hour)}:${pad(p.minute)}`;
}

/** Inverse of toInputValue: the instant at which the working timezone's clock reads this. */
export function fromInputValue(local: string): string {
  const [datePart, timePart = "00:00"] = local.split("T");
  const [y, mo, d] = datePart.split("-").map(Number);
  const [h, mi] = timePart.split(":").map(Number);
  const wanted = Date.UTC(y, mo - 1, d, h, mi);
  // Start from "as if UTC", then correct by what the zone actually shows (twice covers DST edges).
  let guess = wanted;
  for (let i = 0; i < 2; i++) {
    const p = tzParts(new Date(guess));
    const shown = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute);
    guess += wanted - shown;
  }
  return new Date(guess).toISOString();
}

/** The next quarter hour after `now`, as a datetime-local value. */
export function nextQuarterInput(
  now: Date = new Date(),
  plusMinutes = 0,
): string {
  const ms = 15 * 60 * 1000;
  const rounded = new Date(
    Math.ceil(now.getTime() / ms) * ms + plusMinutes * 60 * 1000,
  );
  return toInputValue(rounded.toISOString());
}
