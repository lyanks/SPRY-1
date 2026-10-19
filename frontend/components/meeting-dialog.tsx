"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { useEffect, useState } from "react";
import { useForm } from "react-hook-form";
import { toast } from "sonner";

import { DeleteMeetingButton } from "@/components/delete-meeting-button";
import { PasteAgenda } from "@/components/paste-agenda";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { meetingInputSchema, type Meeting, type MeetingInput } from "@/lib/api";
import { useCreateMeeting, useUpdateMeeting } from "@/lib/queries";
import {
  parserEnabled,
  suggestionToForm,
  type ParseResponse,
  type SuggestedField,
} from "@/lib/parser";
import { fromInputValue, nextQuarterInput, toInputValue } from "@/lib/time";

type Props = {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** Editing when set, creating when null. */
  meeting: Meeting | null;
};

function valuesFor(meeting: Meeting | null): MeetingInput {
  if (meeting) {
    return {
      title: meeting.title,
      starts_at: toInputValue(meeting.starts_at),
      ends_at: toInputValue(meeting.ends_at),
      attendee_count: meeting.attendee_count,
      agenda: meeting.agenda ?? "",
    };
  }
  return {
    title: "",
    starts_at: nextQuarterInput(new Date(), 60),
    ends_at: nextQuarterInput(new Date(), 90),
    attendee_count: 2,
    agenda: "",
  };
}

export function MeetingDialog({ open, onOpenChange, meeting }: Props) {
  const create = useCreateMeeting();
  const update = useUpdateMeeting();
  const saving = create.isPending || update.isPending;

  const form = useForm<MeetingInput>({
    resolver: zodResolver(meetingInputSchema),
    defaultValues: valuesFor(meeting),
  });
  const { errors } = form.formState;

  // Paste an agenda (Lab 6): what the model suggested, and which fields still
  // show its suggestion untouched.
  const [suggestion, setSuggestion] = useState<ParseResponse | null>(null);
  const [suggested, setSuggested] = useState<SuggestedField[]>([]);

  // Re-seed the form each time the dialog opens for a different meeting.
  useEffect(() => {
    if (!open) return;
    form.reset(valuesFor(meeting));
    // Forget the last suggestion when the dialog closes or switches meeting.
    return () => {
      setSuggestion(null);
      setSuggested([]);
    };
  }, [open, meeting, form]);

  // The badge goes away as soon as the person edits that field themselves.
  const register = (name: SuggestedField) =>
    form.register(name, {
      onChange: () => setSuggested((prev) => prev.filter((f) => f !== name)),
    });

  function applySuggestion(result: ParseResponse) {
    const { values, suggested: fields } = suggestionToForm(
      result.agenda,
      form.getValues(),
    );
    for (const [name, value] of Object.entries(values)) {
      form.setValue(name as keyof MeetingInput, value as never, {
        shouldDirty: true,
        shouldValidate: true,
      });
    }
    setSuggestion(result);
    setSuggested(fields);
    toast.success("Form pre-filled. Check it, then save.");
  }

  async function onSubmit(values: MeetingInput) {
    const payload = {
      title: values.title.trim(),
      starts_at: fromInputValue(values.starts_at),
      ends_at: fromInputValue(values.ends_at),
      attendee_count: values.attendee_count,
      agenda: values.agenda.trim() === "" ? null : values.agenda.trim(),
      // What the model suggested goes along, so the API can keep it beside what
      // the person saved: every correction is feedback.
      ...(suggestion && {
        ai_suggestion: {
          model: suggestion.model,
          prompt_version: suggestion.prompt_version,
          agenda: suggestion.agenda,
        },
      }),
    };
    try {
      if (meeting) {
        await update.mutateAsync({ id: meeting.id, payload });
        toast.success("Meeting saved");
      } else {
        await create.mutateAsync(payload);
        toast.success("Meeting added");
      }
      onOpenChange(false);
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Could not save the meeting",
      );
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[34rem]">
        <DialogHeader>
          <DialogTitle>
            {meeting ? "Edit meeting" : "Add a meeting"}
          </DialogTitle>
          <DialogDescription>
            Times are in your working timezone (Europe/Kyiv).
          </DialogDescription>
        </DialogHeader>

        <form
          onSubmit={form.handleSubmit(onSubmit)}
          className="space-y-4"
          noValidate
        >
          {parserEnabled && (
            <PasteAgenda onParsed={applySuggestion} disabled={saving} />
          )}

          <div className="space-y-1.5">
            <Label htmlFor="title">
              Title <Suggested show={suggested.includes("title")} />
            </Label>
            <Input
              id="title"
              placeholder="Weekly product sync"
              aria-invalid={!!errors.title}
              {...register("title")}
            />
            {errors.title && <FieldError>{errors.title.message}</FieldError>}
          </div>

          <div className="grid gap-3 sm:grid-cols-2">
            <div className="space-y-1.5">
              <Label htmlFor="starts_at">
                Starts <Suggested show={suggested.includes("starts_at")} />
              </Label>
              <Input
                id="starts_at"
                type="datetime-local"
                aria-invalid={!!errors.starts_at}
                {...register("starts_at")}
              />
              {errors.starts_at && (
                <FieldError>{errors.starts_at.message}</FieldError>
              )}
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="ends_at">
                Ends <Suggested show={suggested.includes("ends_at")} />
              </Label>
              <Input
                id="ends_at"
                type="datetime-local"
                aria-invalid={!!errors.ends_at}
                {...register("ends_at")}
              />
              {errors.ends_at && (
                <FieldError>{errors.ends_at.message}</FieldError>
              )}
            </div>
          </div>

          <div className="space-y-1.5">
            <Label htmlFor="attendee_count">Attendees</Label>
            <Input
              id="attendee_count"
              type="number"
              min={1}
              max={1000}
              className="w-28"
              aria-invalid={!!errors.attendee_count}
              {...form.register("attendee_count", { valueAsNumber: true })}
            />
            <p className="text-xs text-muted-foreground">
              One person counts as a personal block, not a meeting.
            </p>
            {errors.attendee_count && (
              <FieldError>{errors.attendee_count.message}</FieldError>
            )}
          </div>

          <div className="space-y-1.5">
            <Label htmlFor="agenda">
              Agenda <Suggested show={suggested.includes("agenda")} />
            </Label>
            <Textarea
              id="agenda"
              rows={4}
              placeholder="What should this meeting decide or produce?"
              aria-invalid={!!errors.agenda}
              {...register("agenda")}
            />
            {errors.agenda && <FieldError>{errors.agenda.message}</FieldError>}
          </div>

          <DialogFooter className="items-center sm:justify-end">
            {meeting && (
              <DeleteMeetingButton
                meeting={meeting}
                variant="full"
                onDeleted={() => onOpenChange(false)}
              />
            )}
            <Button
              type="button"
              variant="outline"
              onClick={() => onOpenChange(false)}
              disabled={saving}
            >
              Cancel
            </Button>
            <Button type="submit" disabled={saving}>
              {saving ? "Saving…" : meeting ? "Save changes" : "Add meeting"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

/** Marks a field the model filled in, until the person touches it. */
function Suggested({ show }: { show: boolean }) {
  if (!show) return null;
  return (
    <span className="ml-1 rounded-full bg-violet-soft/20 px-2 py-0.5 text-[0.65rem] font-semibold text-ink">
      suggested
    </span>
  );
}

function FieldError({ children }: { children: React.ReactNode }) {
  return (
    <p role="alert" className="text-xs font-medium text-destructive">
      {children}
    </p>
  );
}
