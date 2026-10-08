"use client";

import { ChevronLeft, ChevronRight, Plus } from "lucide-react";
import { useState } from "react";

import { AgendaCard } from "@/components/agenda-card";
import { DeepWorkCard } from "@/components/deep-work-card";
import { MeetingDialog } from "@/components/meeting-dialog";
import { MetricTiles } from "@/components/metric-tiles";
import { MiniMonth } from "@/components/mini-month";
import { WeekCalendar } from "@/components/week-calendar";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import type { Meeting } from "@/lib/api";
import { useWeekInsights, useWeekMeetings } from "@/lib/queries";
import { addDays, formatWeekRange, mondayOf, todayKey } from "@/lib/time";

type DialogState = { open: boolean; meeting: Meeting | null };

export function Dashboard() {
  const today = todayKey();
  const [weekStart, setWeekStart] = useState(() => mondayOf(today));
  const [dialog, setDialog] = useState<DialogState>({
    open: false,
    meeting: null,
  });

  const insights = useWeekInsights(weekStart);
  const meetings = useWeekMeetings(weekStart);

  const openCreate = () => setDialog({ open: true, meeting: null });
  const openEdit = (meeting: Meeting) => setDialog({ open: true, meeting });
  const isCurrentWeek = weekStart === mondayOf(today);

  return (
    <div className="grid grid-cols-[minmax(0,1fr)] gap-4 xl:grid-cols-[21rem_minmax(0,1fr)]">
      <div className="order-2 space-y-4 xl:order-1">
        <MiniMonth
          weekStart={weekStart}
          today={today}
          onPickWeek={setWeekStart}
        />
        <DeepWorkCard />
        <AgendaCard onAddAgenda={openEdit} />
      </div>

      <div className="order-1 space-y-4 xl:order-2">
        <header className="flex flex-wrap items-center justify-between gap-3 px-1">
          <div>
            <h1 className="text-3xl font-bold tracking-tight text-ink">
              Your week
            </h1>
            <p className="text-sm text-muted-foreground">
              {formatWeekRange(weekStart)}
            </p>
          </div>
          <div className="flex items-center gap-2">
            <Button
              variant="outline"
              size="icon"
              className="bg-card"
              aria-label="Previous week"
              onClick={() => setWeekStart(addDays(weekStart, -7))}
            >
              <ChevronLeft />
            </Button>
            <Button
              variant="outline"
              className="bg-card"
              disabled={isCurrentWeek}
              onClick={() => setWeekStart(mondayOf(today))}
            >
              This week
            </Button>
            <Button
              variant="outline"
              size="icon"
              className="bg-card"
              aria-label="Next week"
              onClick={() => setWeekStart(addDays(weekStart, 7))}
            >
              <ChevronRight />
            </Button>
            <Button onClick={openCreate}>
              <Plus /> Add meeting
            </Button>
          </div>
        </header>

        {insights.isError ? (
          <LoadError
            message="Couldn’t load this week’s numbers."
            onRetry={() => insights.refetch()}
          />
        ) : (
          <MetricTiles insights={insights.data} loading={insights.isLoading} />
        )}

        {meetings.isLoading ? (
          <Skeleton
            className="h-[34rem] rounded-3xl bg-card/70"
            aria-busy="true"
          />
        ) : meetings.isError ? (
          <LoadError
            message="Couldn’t load your meetings."
            onRetry={() => meetings.refetch()}
          />
        ) : (
          <WeekCalendar
            weekStart={weekStart}
            today={today}
            meetings={meetings.data ?? []}
            onSelect={openEdit}
          />
        )}
      </div>

      <MeetingDialog
        open={dialog.open}
        meeting={dialog.meeting}
        onOpenChange={(open) => setDialog((d) => ({ ...d, open }))}
      />
    </div>
  );
}

function LoadError({
  message,
  onRetry,
}: {
  message: string;
  onRetry: () => void;
}) {
  return (
    <div role="alert" className="rounded-3xl bg-card p-5 text-sm">
      <p className="font-medium text-destructive">{message}</p>
      <p className="mt-1 text-muted-foreground">
        Check that the API is running, then try again.
      </p>
      <Button variant="outline" size="sm" className="mt-3" onClick={onRetry}>
        Try again
      </Button>
    </div>
  );
}
