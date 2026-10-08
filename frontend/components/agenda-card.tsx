"use client";

import { CheckCircle2 } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import type { Meeting } from "@/lib/api";
import { useAgendaReadiness } from "@/lib/queries";
import { dayKey, formatDayLong, formatTime } from "@/lib/time";

export function AgendaCard({
  onAddAgenda,
}: {
  onAddAgenda: (meeting: Meeting) => void;
}) {
  const { data, isLoading, isError, refetch } = useAgendaReadiness();

  return (
    <section aria-label="Agenda readiness" className="rounded-3xl bg-card p-5">
      <h2 className="text-base font-semibold text-ink">Agenda readiness</h2>

      {isLoading ? (
        <div className="mt-4 space-y-3" aria-busy="true">
          <Skeleton className="h-10 w-24" />
          <Skeleton className="h-12 w-full rounded-2xl" />
        </div>
      ) : isError || !data ? (
        <div className="mt-3 text-sm">
          <p className="text-destructive">Couldn’t load upcoming meetings.</p>
          <Button
            variant="outline"
            size="sm"
            className="mt-2"
            onClick={() => refetch()}
          >
            Try again
          </Button>
        </div>
      ) : data.upcoming === 0 ? (
        <p className="mt-3 text-sm text-muted-foreground">
          No meetings in the next {data.window_days} days, so nothing needs an
          agenda.
        </p>
      ) : data.without_agenda === 0 ? (
        <p className="mt-3 flex items-center gap-2 text-sm text-ink">
          <CheckCircle2 className="size-5 text-lime-deep" aria-hidden />
          All {data.upcoming} upcoming meetings have an agenda.
        </p>
      ) : (
        <>
          <p className="mt-2 flex items-baseline gap-2">
            <span className="text-4xl font-light tabular-nums text-ink">
              {Math.round(data.without_agenda_pct)}%
            </span>
            <span className="text-sm text-muted-foreground">
              of meetings in the next {data.window_days} days have no agenda
            </span>
          </p>
          <div
            role="progressbar"
            aria-label="Meetings without an agenda"
            aria-valuenow={Math.round(data.without_agenda_pct)}
            aria-valuemin={0}
            aria-valuemax={100}
            className="mt-3 h-2 overflow-hidden rounded-full bg-accent"
          >
            <div
              className="h-full rounded-full bg-violet-soft"
              style={{ width: `${data.without_agenda_pct}%` }}
            />
          </div>
          <ul className="mt-4 space-y-2">
            {data.meetings.slice(0, 5).map((m) => (
              <li
                key={m.id}
                className="flex items-center justify-between gap-3 rounded-2xl bg-lilac px-3 py-2.5"
              >
                <div className="min-w-0">
                  <p className="truncate text-sm font-semibold text-ink">
                    {m.title}
                  </p>
                  <p className="text-xs text-muted-foreground tabular-nums">
                    {formatDayLong(dayKey(m.starts_at))},{" "}
                    {formatTime(m.starts_at)}
                  </p>
                </div>
                <Button
                  variant="outline"
                  size="sm"
                  className="shrink-0 bg-white"
                  onClick={() => onAddAgenda(m)}
                  aria-label={`Add agenda to ${m.title}`}
                >
                  Add agenda
                </Button>
              </li>
            ))}
          </ul>
        </>
      )}
    </section>
  );
}
