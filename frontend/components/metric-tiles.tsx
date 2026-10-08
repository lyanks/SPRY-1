import { ArrowDownRight, ArrowUpRight, Minus } from "lucide-react";

import { Skeleton } from "@/components/ui/skeleton";
import type { Metric, WeekInsights } from "@/lib/api";
import { hoursOf } from "@/lib/time";
import { cn } from "@/lib/utils";

type TileProps = {
  label: string;
  metric: Metric;
  /** How to show the value: hours from minutes, or a plain count. */
  format: "hours" | "count";
  /** Fewer meetings is good news, more deep work is good news. */
  better: "down" | "up";
};

function Change({ metric, better }: { metric: Metric; better: "down" | "up" }) {
  if (metric.change_pct === null) {
    return (
      <span className="inline-flex items-center gap-1 text-xs text-muted-foreground">
        <Minus className="size-3.5" aria-hidden /> Nothing to compare yet
      </span>
    );
  }
  const up = metric.change_pct > 0;
  const flat = metric.change_pct === 0;
  const good = flat ? null : up === (better === "up");
  const Icon = flat ? Minus : up ? ArrowUpRight : ArrowDownRight;
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-semibold",
        good === null && "bg-accent text-muted-foreground",
        good === true && "bg-lime text-ink",
        good === false && "bg-[#f6dcd6] text-[#8a2f1f]",
      )}
    >
      <Icon className="size-3.5" aria-hidden />
      {flat ? "No change" : `${Math.abs(metric.change_pct)}%`}
      <span className="font-normal opacity-80">vs last week</span>
    </span>
  );
}

function Tile({ label, metric, format, better }: TileProps) {
  const value =
    format === "hours" ? hoursOf(metric.value) : String(metric.value);
  return (
    <div className="rounded-3xl bg-card p-5 shadow-[0_1px_0_rgba(75,58,140,0.06)]">
      <p className="text-sm font-medium text-muted-foreground">{label}</p>
      <p className="mt-2 flex items-baseline gap-1.5 text-5xl font-light tracking-tight text-ink tabular-nums">
        {value}
        {format === "hours" && (
          <span className="text-base font-medium text-muted-foreground">
            hours
          </span>
        )}
      </p>
      <div className="mt-3">
        <Change metric={metric} better={better} />
      </div>
    </div>
  );
}

export function MetricTiles({
  insights,
  loading,
}: {
  insights: WeekInsights | undefined;
  loading: boolean;
}) {
  if (loading || !insights) {
    return (
      <div className="grid gap-3 sm:grid-cols-3" aria-busy="true">
        {[0, 1, 2].map((i) => (
          <Skeleton key={i} className="h-[9.5rem] rounded-3xl bg-card/70" />
        ))}
      </div>
    );
  }
  return (
    <div className="grid gap-3 sm:grid-cols-3">
      <Tile
        label="Time in meetings"
        metric={insights.meeting_minutes}
        format="hours"
        better="down"
      />
      <Tile
        label="Meetings"
        metric={insights.meeting_count}
        format="count"
        better="down"
      />
      <Tile
        label="Deep work time"
        metric={insights.deep_work_minutes}
        format="hours"
        better="up"
      />
    </div>
  );
}
