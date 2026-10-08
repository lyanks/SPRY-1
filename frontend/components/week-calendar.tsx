"use client";

import { ClipboardX } from "lucide-react";

import type { Meeting } from "@/lib/api";
import {
  DAY_END_HOUR,
  DAY_START_HOUR,
  dayKey,
  formatTime,
  minuteOfDay,
  weekDays,
} from "@/lib/time";
import { cn } from "@/lib/utils";

export const HOUR_PX = 52;
const WORK_START = 9;
const WORK_END = 18;

type Placed = {
  meeting: Meeting;
  start: number;
  end: number;
  lane: number;
  lanes: number;
};

/** Minutes from midnight on the day the meeting starts; clipped at midnight. */
function span(m: Meeting): { start: number; end: number } {
  const start = minuteOfDay(m.starts_at);
  const sameDay = dayKey(m.starts_at) === dayKey(m.ends_at);
  const end = sameDay ? minuteOfDay(m.ends_at) : 24 * 60;
  return { start, end: Math.max(end, start + 15) };
}

/** Place overlapping meetings side by side instead of on top of each other. */
export function layoutDay(meetings: Meeting[]): Placed[] {
  const sorted = meetings
    .map((meeting) => ({ meeting, ...span(meeting) }))
    .sort((a, b) => a.start - b.start || a.end - b.end);

  const placed: Placed[] = [];
  let cluster: Placed[] = [];
  let laneEnds: number[] = [];
  let clusterEnd = -1;

  const flush = () => {
    for (const p of cluster) p.lanes = laneEnds.length;
    placed.push(...cluster);
    cluster = [];
    laneEnds = [];
  };

  for (const item of sorted) {
    if (item.start >= clusterEnd && cluster.length > 0) flush();
    let lane = laneEnds.findIndex((end) => end <= item.start);
    if (lane === -1) {
      lane = laneEnds.length;
      laneEnds.push(item.end);
    } else {
      laneEnds[lane] = item.end;
    }
    clusterEnd =
      cluster.length === 0 ? item.end : Math.max(clusterEnd, item.end);
    cluster.push({ ...item, lane, lanes: 1 });
  }
  flush();
  return placed;
}

const KIND_STYLE: Record<Meeting["kind"], string> = {
  meeting: "border-l-violet-soft bg-[#ddd5f7] text-ink hover:bg-[#d1c7f3]",
  focus: "border-l-lime-deep bg-lime text-ink hover:bg-[#b6e552]",
  other:
    "border-l-[#a79fc4] bg-white text-ink ring-1 ring-inset ring-border hover:bg-lilac",
};

type Props = {
  weekStart: string;
  today: string;
  meetings: Meeting[];
  onSelect: (meeting: Meeting) => void;
};

export function WeekCalendar({ weekStart, today, meetings, onSelect }: Props) {
  const all = weekDays(weekStart);
  const byDay = new Map<string, Meeting[]>();
  for (const m of meetings) {
    const key = dayKey(m.starts_at);
    if (key >= all[0] && key <= all[6])
      byDay.set(key, [...(byDay.get(key) ?? []), m]);
  }
  // Show the weekend only when something is booked on it.
  const days = byDay.has(all[5]) || byDay.has(all[6]) ? all : all.slice(0, 5);

  const spans = [...byDay.values()].flat().map(span);
  const firstHour = Math.min(
    DAY_START_HOUR,
    ...spans.map((s) => Math.floor(s.start / 60)),
  );
  const lastHour = Math.max(
    DAY_END_HOUR,
    ...spans.map((s) => Math.ceil(s.end / 60)),
  );
  const hours = Array.from(
    { length: lastHour - firstHour },
    (_, i) => firstHour + i,
  );
  const height = hours.length * HOUR_PX;

  const nowKey = dayKey(new Date());
  const nowMinutes = minuteOfDay(new Date());
  const showNow =
    days.includes(nowKey) &&
    nowMinutes >= firstHour * 60 &&
    nowMinutes < lastHour * 60;

  const cols = `3rem repeat(${days.length}, minmax(0, 1fr))`;

  return (
    <section
      aria-label="Week calendar"
      className="overflow-hidden rounded-3xl bg-card"
    >
      <div
        className="grid border-b border-border"
        style={{ gridTemplateColumns: cols }}
      >
        <div />
        {days.map((day) => {
          const isToday = day === today;
          return (
            <div key={day} className="flex flex-col items-center gap-1 py-3">
              <span className="text-xs font-medium text-muted-foreground">
                {new Intl.DateTimeFormat("en-GB", {
                  timeZone: "UTC",
                  weekday: "short",
                }).format(new Date(`${day}T00:00:00Z`))}
              </span>
              <span
                className={cn(
                  "grid size-9 place-items-center rounded-full text-lg font-semibold tabular-nums",
                  isToday ? "bg-violet text-white" : "text-ink",
                )}
              >
                {Number(day.slice(8))}
              </span>
            </div>
          );
        })}
      </div>

      <div className="overflow-x-auto">
        <div
          className="relative grid min-w-[34rem]"
          style={{ gridTemplateColumns: cols, height }}
        >
          <div className="relative">
            {hours.map((h) => (
              <span
                key={h}
                className="absolute right-2 -translate-y-1/2 text-[11px] text-muted-foreground tabular-nums"
                style={{
                  top: (h - firstHour) * HOUR_PX,
                  display: h === firstHour ? "none" : "block",
                }}
              >
                {String(h).padStart(2, "0")}:00
              </span>
            ))}
          </div>

          {days.map((day) => {
            const placed = layoutDay(byDay.get(day) ?? []);
            return (
              <div
                key={day}
                data-testid={`day-${day}`}
                className={cn(
                  "relative border-l border-border",
                  day === today && "bg-accent/50",
                )}
              >
                {/* working hours band */}
                <div
                  aria-hidden
                  className="absolute inset-x-0 bg-lilac/70"
                  style={{
                    top: (WORK_START - firstHour) * HOUR_PX,
                    height: (WORK_END - WORK_START) * HOUR_PX,
                    display: WORK_START >= firstHour ? "block" : "none",
                  }}
                />
                {hours.map((h) => (
                  <div
                    key={h}
                    aria-hidden
                    className="absolute inset-x-0 border-t border-border/60"
                    style={{ top: (h - firstHour) * HOUR_PX }}
                  />
                ))}

                {day === nowKey && showNow && (
                  <div
                    aria-hidden
                    className="absolute inset-x-0 z-20 h-0.5 bg-violet"
                    style={{
                      top: ((nowMinutes - firstHour * 60) / 60) * HOUR_PX,
                    }}
                  >
                    <span className="absolute -left-1 -top-[3px] size-2 rounded-full bg-violet" />
                  </div>
                )}

                {placed.map(({ meeting, start, end, lane, lanes }) => {
                  const top = ((start - firstHour * 60) / 60) * HOUR_PX;
                  const blockHeight = Math.max(
                    ((end - start) / 60) * HOUR_PX - 2,
                    22,
                  );
                  const missingAgenda =
                    meeting.kind === "meeting" && !meeting.has_agenda;
                  return (
                    <button
                      key={meeting.id}
                      type="button"
                      onClick={() => onSelect(meeting)}
                      aria-label={`${meeting.title}, ${formatTime(meeting.starts_at)} to ${formatTime(meeting.ends_at)}${missingAgenda ? ", no agenda" : ""}`}
                      className={cn(
                        "absolute z-10 overflow-hidden rounded-lg border-l-4 px-2 py-1 text-left text-xs outline-none transition-colors focus-visible:ring-2 focus-visible:ring-violet",
                        KIND_STYLE[meeting.kind],
                      )}
                      style={{
                        top,
                        height: blockHeight,
                        left: `calc(${(lane / lanes) * 100}% + 2px)`,
                        width: `calc(${100 / lanes}% - 4px)`,
                      }}
                    >
                      <span className="block truncate font-semibold leading-tight">
                        {meeting.title}
                      </span>
                      {blockHeight > 36 && (
                        <span className="block truncate text-[11px] opacity-75">
                          {formatTime(meeting.starts_at)} –{" "}
                          {formatTime(meeting.ends_at)}
                        </span>
                      )}
                      {missingAgenda && (
                        <ClipboardX
                          aria-hidden
                          className="absolute right-1 top-1 size-3.5 text-violet"
                        />
                      )}
                    </button>
                  );
                })}
              </div>
            );
          })}
        </div>
      </div>

      <ul className="flex flex-wrap items-center gap-x-5 gap-y-1 border-t border-border px-5 py-3 text-xs text-muted-foreground">
        <li className="flex items-center gap-1.5">
          <span className="size-3 rounded-sm bg-[#ddd5f7] ring-1 ring-violet-soft/40" />{" "}
          Meeting
        </li>
        <li className="flex items-center gap-1.5">
          <span className="size-3 rounded-sm bg-lime" /> Deep work block
        </li>
        <li className="flex items-center gap-1.5">
          <span className="size-3 rounded-sm bg-white ring-1 ring-border" />{" "}
          Other
        </li>
        <li className="flex items-center gap-1.5">
          <ClipboardX className="size-3.5 text-violet" aria-hidden /> No agenda
          yet
        </li>
      </ul>
    </section>
  );
}
