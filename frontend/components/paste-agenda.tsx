"use client";

import { ClipboardPaste, Loader2, Sparkles } from "lucide-react";
import { useEffect, useRef, useState } from "react";

import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  MAX_PASTE_CHARS,
  ParseError,
  parseAgenda,
  type ParseResponse,
} from "@/lib/parser";

/**
 * "Paste an agenda": text in, a suggestion out. It never saves anything; the
 * parent pre-fills its form with the result and the person decides.
 */
export function PasteAgenda({
  onParsed,
  disabled,
}: {
  onParsed: (result: ParseResponse) => void;
  disabled?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [text, setText] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const controller = useRef<AbortController | null>(null);

  // Leaving the dialog must not leave a request (and its cost) running.
  useEffect(() => () => controller.current?.abort(), []);

  const tooLong = text.length > MAX_PASTE_CHARS;

  async function run() {
    setError(null);
    setPending(true);
    const ctl = new AbortController();
    controller.current = ctl;
    try {
      const result = await parseAgenda(text, { signal: ctl.signal });
      onParsed(result);
      setOpen(false);
      setText("");
    } catch (err) {
      if (err instanceof DOMException && err.name === "AbortError") return;
      setError(
        err instanceof ParseError ? err.message : "Something went wrong.",
      );
    } finally {
      if (controller.current === ctl) {
        controller.current = null;
        setPending(false);
      }
    }
  }

  function cancel() {
    controller.current?.abort();
    controller.current = null;
    setPending(false);
  }

  if (!open) {
    return (
      <Button
        type="button"
        variant="outline"
        size="sm"
        className="self-start"
        onClick={() => setOpen(true)}
        disabled={disabled}
      >
        <ClipboardPaste aria-hidden /> Paste an agenda
      </Button>
    );
  }

  return (
    <div className="space-y-2 rounded-2xl bg-lilac p-3">
      <Label htmlFor="paste-agenda">Paste an agenda</Label>
      <Textarea
        id="paste-agenda"
        rows={5}
        className="bg-white"
        placeholder="Paste an email, a chat message or your notes. The form below is filled in for you to check."
        value={text}
        onChange={(e) => setText(e.target.value)}
        disabled={pending}
        aria-invalid={tooLong}
      />
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p
          className={`text-xs tabular-nums ${tooLong ? "font-medium text-destructive" : "text-muted-foreground"}`}
        >
          {text.length.toLocaleString("en")} /{" "}
          {MAX_PASTE_CHARS.toLocaleString("en")}
        </p>
        <div className="flex items-center gap-2">
          {pending ? (
            <>
              <span
                role="status"
                className="flex items-center gap-1.5 text-xs text-muted-foreground"
              >
                <Loader2 className="size-3.5 animate-spin" aria-hidden />
                Reading your text… usually 2–8 seconds
              </span>
              <Button
                type="button"
                variant="outline"
                size="sm"
                onClick={cancel}
                aria-label="Cancel parsing"
              >
                Cancel
              </Button>
            </>
          ) : (
            <>
              <Button
                type="button"
                variant="ghost"
                size="sm"
                onClick={() => {
                  setOpen(false);
                  setError(null);
                }}
              >
                Close
              </Button>
              <Button
                type="button"
                size="sm"
                onClick={run}
                disabled={!text.trim() || tooLong}
              >
                <Sparkles aria-hidden /> Parse
              </Button>
            </>
          )}
        </div>
      </div>
      {error && (
        <p role="alert" className="text-xs font-medium text-destructive">
          {error}
        </p>
      )}
    </div>
  );
}
