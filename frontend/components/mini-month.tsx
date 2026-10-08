"use client";

import { ChevronLeft, ChevronRight } from "lucide-react";
import { useState } from "react";

import { addDays, formatMonthYear, mondayOf } from "@/lib/time";
import { cn } from "@/lib/utils";

const WEEKDAYS = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"];

type Props = {
  /** Monday of the week shown on the dashboard. */
  weekStart: string;
  today: string;
  onPickWeek: (weekStart: string) => void;
};

function shiftMonth(firstOfMonth: string, delta: number): string {
  const d = new Date(`${firstOfMonth}T00:00:00Z`);
  d.setUTCMonth(d.getUTCMonth() + delta, 1);
  return d.toISOString().slice(0, 10);
}

export function MiniMonth({ weekStart, today, onPickWeek }: Props) {
  const [month, setMonth] = useState(`${weekStart.slice(0, 7)}-01`);

  const gridStart = mondayOf(month);
  const days = Array.from({ length: 42 }, (_, i) => addDays(gridStart, i));
  const weekEnd = addDays(weekStart, 6);

  return (
    <section
      aria-label="Pick a week"
      className="rounded-3xl bg-violet p-5 text-white"
    >
      <div className="flex items-center justify-between">
        <h2 className="text-base font-semibold">{formatMonthYear(month)}</h2>
        <div className="flex gap-1">
          <button
            type="button"
            aria-label="Previous month"
            className="grid size-7 place-items-center rounded-full bg-white/15 outline-none hover:bg-white/25 focus-visible:ring-2 focus-visible:ring-lime"
            onClick={() => setMonth(shiftMonth(month, -1))}
          >
            <ChevronLeft className="size-4" />
          </button>
          <button
            type="button"
            aria-label="Next month"
            className="grid size-7 place-items-center rounded-full bg-white/15 outline-none hover:bg-white/25 focus-visible:ring-2 focus-visible:ring-lime"
            onClick={() => setMonth(shiftMonth(month, 1))}
          >
            <ChevronRight className="size-4" />
          </button>
        </div>
      </div>

      <div className="mt-4 grid grid-cols-7 gap-y-1 text-center text-xs">
        {WEEKDAYS.map((d) => (
          <span key={d} className="pb-1 text-white/60">
            {d}
          </span>
        ))}
        {days.map((day) => {
          const inMonth = day.slice(0, 7) === month.slice(0, 7);
          const inWeek = day >= weekStart && day <= weekEnd;
          const isToday = day === today;
          return (
            <button
              key={day}
              type="button"
              aria-label={day}
              aria-current={isToday ? "date" : undefined}
              aria-pressed={inWeek}
              onClick={() => onPickWeek(mondayOf(day))}
              className={cn(
                "mx-auto grid h-8 w-full place-items-center text-[13px] outline-none transition-colors focus-visible:ring-2 focus-visible:ring-lime",
                inWeek && "bg-white/20",
                day === weekStart && "rounded-l-full",
                day === weekEnd && "rounded-r-full",
                !inWeek && "rounded-full hover:bg-white/10",
                !inMonth && "text-white/35",
                isToday && "font-bold",
              )}
            >
              <span
                className={cn(
                  "grid size-7 place-items-center rounded-full",
                  isToday && "bg-lime text-ink",
                )}
              >
                {Number(day.slice(8))}
              </span>
            </button>
          );
        })}
      </div>
    </section>
  );
}
