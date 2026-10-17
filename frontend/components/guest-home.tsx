"use client";

import { CalendarCheck, Clock, LogIn, ShieldCheck } from "lucide-react";
import Link from "next/link";
import { useMemo } from "react";

import { MetricTiles } from "@/components/metric-tiles";
import { WeekCalendar } from "@/components/week-calendar";
import { Button } from "@/components/ui/button";
import { demoInsights, demoMeetings } from "@/lib/demo";
import { formatWeekRange, mondayOf, todayKey } from "@/lib/time";

/**
 * What a visitor who is not signed in sees: what Spry is, a way in, and a
 * read-only sample of the current week. Editing needs an account, and every
 * account has its own calendar - the sample is not anyone's.
 */
export function GuestHome() {
  const today = todayKey();
  const weekStart = mondayOf(today);
  const meetings = useMemo(() => demoMeetings(weekStart), [weekStart]);
  const insights = useMemo(() => demoInsights(weekStart), [weekStart]);

  return (
    <div className="space-y-6">
      <section className="rounded-3xl bg-violet p-8 text-white md:p-10">
        <h1 className="max-w-2xl text-4xl font-bold tracking-tight md:text-5xl">
          See where your week goes. Protect time for deep work.
        </h1>
        <p className="mt-4 max-w-xl text-white/80">
          Spry reads your calendar, shows how much of the week meetings take,
          flags meetings with no agenda and proposes free blocks for focused
          work.
        </p>
        <ul className="mt-5 flex flex-wrap gap-x-6 gap-y-2 text-sm text-white/90">
          <li className="flex items-center gap-2">
            <Clock className="size-4 text-lime" aria-hidden /> Meeting load,
            week over week
          </li>
          <li className="flex items-center gap-2">
            <CalendarCheck className="size-4 text-lime" aria-hidden /> Agenda
            checks
          </li>
          <li className="flex items-center gap-2">
            <ShieldCheck className="size-4 text-lime" aria-hidden /> Your
            calendar is private to you
          </li>
        </ul>
        <div className="mt-7">
          <Button
            asChild
            size="lg"
            className="bg-lime text-ink hover:bg-lime/90"
          >
            <Link href="/login">
              <LogIn data-icon="inline-start" />
              Sign in or create an account
            </Link>
          </Button>
        </div>
      </section>

      <section aria-labelledby="sample-heading" className="space-y-4">
        <header className="px-1">
          <h2
            id="sample-heading"
            className="text-2xl font-bold tracking-tight text-ink"
          >
            A sample week
          </h2>
          <p className="text-sm text-muted-foreground">
            {formatWeekRange(weekStart)} · made-up meetings, read-only. Sign in
            to build your own.
          </p>
        </header>
        <MetricTiles insights={insights} loading={false} />
        <WeekCalendar weekStart={weekStart} today={today} meetings={meetings} />
      </section>
    </div>
  );
}
