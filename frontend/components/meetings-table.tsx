"use client";

import { Pencil, Plus } from "lucide-react";
import { useState } from "react";

import { DeleteMeetingButton } from "@/components/delete-meeting-button";
import { MeetingDialog } from "@/components/meeting-dialog";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import type { Meeting } from "@/lib/api";
import { useAllMeetings } from "@/lib/queries";
import { dayKey, formatDayLong, formatDuration, formatTime } from "@/lib/time";

const KIND_LABEL: Record<Meeting["kind"], string> = {
  meeting: "Meeting",
  focus: "Deep work",
  other: "Other",
};

export function MeetingsTable() {
  const { data, isLoading, isError, refetch } = useAllMeetings();
  const [dialog, setDialog] = useState<{
    open: boolean;
    meeting: Meeting | null;
  }>({
    open: false,
    meeting: null,
  });

  return (
    <div className="space-y-4">
      <header className="flex flex-wrap items-center justify-between gap-3 px-1">
        <div>
          <h1 className="text-3xl font-bold tracking-tight text-ink">
            Meetings
          </h1>
          <p className="text-sm text-muted-foreground">
            Everything Spry knows about, oldest first.
          </p>
        </div>
        <Button onClick={() => setDialog({ open: true, meeting: null })}>
          <Plus /> Add meeting
        </Button>
      </header>

      <section className="overflow-hidden rounded-3xl bg-card">
        {isLoading ? (
          <div className="space-y-2 p-5" aria-busy="true">
            {[0, 1, 2, 3].map((i) => (
              <Skeleton key={i} className="h-12 w-full rounded-xl" />
            ))}
          </div>
        ) : isError ? (
          <div role="alert" className="p-6 text-sm">
            <p className="font-medium text-destructive">
              Couldn’t load meetings.
            </p>
            <p className="mt-1 text-muted-foreground">
              Check that the API is running.
            </p>
            <Button
              variant="outline"
              size="sm"
              className="mt-3"
              onClick={() => refetch()}
            >
              Try again
            </Button>
          </div>
        ) : !data || data.length === 0 ? (
          <div className="p-10 text-center">
            <p className="font-semibold text-ink">No meetings yet</p>
            <p className="mt-1 text-sm text-muted-foreground">
              Add one and your weekly numbers appear on the dashboard.
            </p>
            <Button
              className="mt-4"
              onClick={() => setDialog({ open: true, meeting: null })}
            >
              <Plus /> Add meeting
            </Button>
          </div>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="pl-5">Title</TableHead>
                <TableHead>When</TableHead>
                <TableHead>Length</TableHead>
                <TableHead>Type</TableHead>
                <TableHead>Agenda</TableHead>
                <TableHead className="pr-5 text-right">Actions</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {data.map((m) => {
                const minutes =
                  (Date.parse(m.ends_at) - Date.parse(m.starts_at)) / 60000;
                return (
                  <TableRow key={m.id}>
                    <TableCell className="pl-5 font-medium text-ink">
                      {m.title}
                    </TableCell>
                    <TableCell className="tabular-nums">
                      {formatDayLong(dayKey(m.starts_at))},{" "}
                      {formatTime(m.starts_at)}
                    </TableCell>
                    <TableCell className="tabular-nums">
                      {formatDuration(minutes)}
                    </TableCell>
                    <TableCell>
                      <Badge
                        variant="secondary"
                        className={
                          m.kind === "focus"
                            ? "bg-lime text-ink"
                            : "bg-accent text-ink"
                        }
                      >
                        {KIND_LABEL[m.kind]}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-muted-foreground">
                      {m.kind !== "meeting"
                        ? "—"
                        : m.has_agenda
                          ? "Added"
                          : "Missing"}
                    </TableCell>
                    <TableCell className="pr-5">
                      <div className="flex justify-end gap-1">
                        <Button
                          variant="ghost"
                          size="icon"
                          aria-label={`Edit ${m.title}`}
                          onClick={() => setDialog({ open: true, meeting: m })}
                        >
                          <Pencil />
                        </Button>
                        <DeleteMeetingButton meeting={m} />
                      </div>
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        )}
      </section>

      <MeetingDialog
        open={dialog.open}
        meeting={dialog.meeting}
        onOpenChange={(open) => setDialog((d) => ({ ...d, open }))}
      />
    </div>
  );
}
