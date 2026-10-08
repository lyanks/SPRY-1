"use client";

import { Trash2 } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";

import {
  AlertDialog,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { Button } from "@/components/ui/button";
import type { Meeting } from "@/lib/api";
import { useDeleteMeeting } from "@/lib/queries";

type Props = {
  meeting: Meeting;
  /** "icon" for table rows, "full" for the edit dialog footer. */
  variant?: "icon" | "full";
  onDeleted?: () => void;
};

export function DeleteMeetingButton({
  meeting,
  variant = "icon",
  onDeleted,
}: Props) {
  const [open, setOpen] = useState(false);
  const remove = useDeleteMeeting();

  async function confirm() {
    try {
      await remove.mutateAsync(meeting.id);
      toast.success("Meeting deleted");
      setOpen(false);
      onDeleted?.();
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Could not delete the meeting",
      );
    }
  }

  return (
    <>
      {variant === "icon" ? (
        <Button
          type="button"
          variant="ghost"
          size="icon"
          aria-label={`Delete ${meeting.title}`}
          className="text-destructive hover:bg-destructive/10 hover:text-destructive"
          onClick={() => setOpen(true)}
        >
          <Trash2 />
        </Button>
      ) : (
        <Button
          type="button"
          variant="ghost"
          className="mr-auto text-destructive hover:bg-destructive/10 hover:text-destructive"
          onClick={() => setOpen(true)}
        >
          <Trash2 /> Delete meeting
        </Button>
      )}
      <AlertDialog open={open} onOpenChange={setOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete this meeting?</AlertDialogTitle>
            <AlertDialogDescription>
              “{meeting.title}” will be removed and your weekly numbers will
              update. This can’t be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={remove.isPending}>
              Keep meeting
            </AlertDialogCancel>
            <Button
              type="button"
              variant="destructive"
              disabled={remove.isPending}
              onClick={confirm}
            >
              {remove.isPending ? "Deleting…" : "Delete meeting"}
            </Button>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}
