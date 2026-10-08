"use client";

import { Lock } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import type { Slot } from "@/lib/api";
import { useDeepWorkSlots, useReserveDeepWork } from "@/lib/queries";
import {
  formatDayLong,
  formatDuration,
  formatTime,
  dayKey,
  hoursOf,
} from "@/lib/time";

const BLOCK_MINUTES = 120;
const MAX_SHOWN = 4;

export function DeepWorkCard() {
  const { data, isLoading, isError, refetch } = useDeepWorkSlots();
  const reserve = useReserveDeepWork();

  async function reserveFirstBlock(slot: Slot) {
    // A free stretch can be a whole day; reserve the first two hours of it.
    const start = new Date(slot.starts_at);
    const end = new Date(
      start.getTime() + Math.min(slot.minutes, BLOCK_MINUTES) * 60_000,
    );
    try {
      await reserve.mutateAsync({
        starts_at: start.toISOString(),
        ends_at: end.toISOString(),
      });
      toast.success("Deep work time reserved");
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Could not reserve that time",
      );
    }
  }

  return (
    <section aria-label="Deep work" className="rounded-3xl bg-card p-5">
      <h2 className="text-base font-semibold text-ink">Deep work</h2>

      {isLoading ? (
        <div className="mt-4 space-y-3" aria-busy="true">
          <Skeleton className="h-6 w-2/3" />
          <Skeleton className="h-14 w-full rounded-2xl" />
          <Skeleton className="h-14 w-full rounded-2xl" />
        </div>
      ) : isError || !data ? (
        <div className="mt-3 text-sm">
          <p className="text-destructive">Couldn’t load free time.</p>
          <Button
            variant="outline"
            size="sm"
            className="mt-2"
            onClick={() => refetch()}
          >
            Try again
          </Button>
        </div>
      ) : data.slots.length === 0 ? (
        <p className="mt-3 text-sm text-muted-foreground">
          No free stretch of 2 hours or more is left this week or next. Move a
          meeting to open one.
        </p>
      ) : (
        <>
          <p className="mt-1 text-sm text-muted-foreground">
            {data.slots.length} {data.slots.length === 1 ? "slot" : "slots"},{" "}
            <span className="font-semibold text-ink">
              {hoursOf(data.total_minutes)} h
            </span>{" "}
            free across this week and next.
          </p>
          <ul className="mt-4 space-y-2">
            {data.slots.slice(0, MAX_SHOWN).map((slot) => (
              <li
                key={slot.starts_at}
                className="flex items-center justify-between gap-3 rounded-2xl bg-lilac px-3 py-2.5"
              >
                <div className="min-w-0">
                  <p className="truncate text-sm font-semibold text-ink">
                    {formatDayLong(dayKey(slot.starts_at))}
                  </p>
                  <p className="text-xs text-muted-foreground tabular-nums">
                    {formatTime(slot.starts_at)} – {formatTime(slot.ends_at)} ·{" "}
                    {formatDuration(slot.minutes)} free
                  </p>
                </div>
                <Button
                  size="sm"
                  className="shrink-0 bg-lime text-ink hover:bg-[#b6e552]"
                  disabled={reserve.isPending}
                  onClick={() => reserveFirstBlock(slot)}
                  aria-label={`Reserve ${formatDuration(Math.min(slot.minutes, BLOCK_MINUTES))} on ${formatDayLong(dayKey(slot.starts_at))}`}
                >
                  <Lock /> Reserve {Math.min(slot.minutes, BLOCK_MINUTES) / 60}{" "}
                  h
                </Button>
              </li>
            ))}
          </ul>
          {data.slots.length > MAX_SHOWN && (
            <p className="mt-3 text-xs text-muted-foreground">
              + {data.slots.length - MAX_SHOWN} more later in the two weeks
            </p>
          )}
        </>
      )}
    </section>
  );
}
