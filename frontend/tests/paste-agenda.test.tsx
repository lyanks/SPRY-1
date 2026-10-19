import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

import { MeetingDialog } from "@/components/meeting-dialog";
import { api } from "@/lib/api";
import * as parser from "@/lib/parser";

import { makeMeeting, renderWithQuery } from "./utils";

vi.mock("@/lib/parser", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/lib/parser")>()),
  parserEnabled: true,
  parseAgenda: vi.fn(),
}));

const RESPONSE: parser.ParseResponse = {
  model: "anthropic.claude-opus-5-5",
  prompt_version: "agenda-v1",
  agenda: {
    title: "Pricing sync",
    starts_at: "2026-10-19T10:00:00+03:00",
    duration_minutes: 45,
    items: [{ topic: "New Pro prices", owner: "Olena", minutes: 15 }],
    action_items: [],
    language: "en",
  },
};

async function pasteAndParse() {
  await userEvent.click(
    screen.getByRole("button", { name: /paste an agenda/i }),
  );
  await userEvent.type(
    screen.getByLabelText("Paste an agenda"),
    "Mon 10:00 sync",
  );
  await userEvent.click(screen.getByRole("button", { name: "Parse" }));
}

describe("Paste an agenda in the meeting dialog", () => {
  it("pre-fills the form, marks suggested fields, and clears a mark when the person edits", async () => {
    vi.mocked(parser.parseAgenda).mockResolvedValue(RESPONSE);
    renderWithQuery(
      <MeetingDialog open onOpenChange={() => {}} meeting={null} />,
    );
    await pasteAndParse();

    await waitFor(() =>
      expect(screen.getByLabelText(/^Title/)).toHaveValue("Pricing sync"),
    );
    expect(screen.getByLabelText(/^Starts/)).toHaveValue("2026-10-19T10:00");
    expect(screen.getByLabelText(/^Ends/)).toHaveValue("2026-10-19T10:45");
    expect(screen.getByLabelText(/^Agenda/)).toHaveValue(
      "1. New Pro prices — Olena, 15 min",
    );
    expect(screen.getAllByText("suggested")).toHaveLength(4);

    await userEvent.type(screen.getByLabelText(/^Title/), "!");
    expect(screen.getAllByText("suggested")).toHaveLength(3);
  });

  it("saves through the normal endpoint and sends the suggestion along", async () => {
    vi.mocked(parser.parseAgenda).mockResolvedValue(RESPONSE);
    const create = vi
      .spyOn(api, "createMeeting")
      .mockResolvedValue(makeMeeting());
    renderWithQuery(
      <MeetingDialog open onOpenChange={() => {}} meeting={null} />,
    );
    await pasteAndParse();
    await waitFor(() =>
      expect(screen.getByLabelText(/^Title/)).toHaveValue("Pricing sync"),
    );

    await userEvent.type(screen.getByLabelText(/^Title/), " (fixed)");
    await userEvent.click(screen.getByRole("button", { name: "Add meeting" }));

    await waitFor(() => expect(create).toHaveBeenCalledTimes(1));
    const payload = create.mock.calls[0][0];
    expect(payload.title).toBe("Pricing sync (fixed)"); // what the person saved
    expect(payload.ai_suggestion).toEqual({
      model: "anthropic.claude-opus-5-5",
      prompt_version: "agenda-v1",
      agenda: RESPONSE.agenda, // what the model suggested
    });
  });

  it("sends no suggestion when nothing was pasted", async () => {
    const create = vi
      .spyOn(api, "createMeeting")
      .mockResolvedValue(makeMeeting());
    renderWithQuery(
      <MeetingDialog open onOpenChange={() => {}} meeting={null} />,
    );
    await userEvent.type(screen.getByLabelText(/^Title/), "Standup");
    await userEvent.click(screen.getByRole("button", { name: "Add meeting" }));
    await waitFor(() => expect(create).toHaveBeenCalledTimes(1));
    expect(create.mock.calls[0][0]).not.toHaveProperty("ai_suggestion");
  });

  it("shows a clear message and keeps the form usable when parsing fails", async () => {
    vi.mocked(parser.parseAgenda).mockRejectedValue(
      new parser.ParseError("busy"),
    );
    renderWithQuery(
      <MeetingDialog open onOpenChange={() => {}} meeting={null} />,
    );
    await pasteAndParse();
    expect(await screen.findByRole("alert")).toHaveTextContent(/busy/i);
    await userEvent.type(screen.getByLabelText(/^Title/), "By hand");
    expect(screen.getByLabelText(/^Title/)).toHaveValue("By hand");
  });

  it("cancels a parse in flight", async () => {
    let signal: AbortSignal | undefined;
    vi.mocked(parser.parseAgenda).mockImplementation(
      (_text, options) =>
        new Promise((_resolve, reject) => {
          signal = options?.signal;
          signal?.addEventListener("abort", () =>
            reject(new DOMException("aborted", "AbortError")),
          );
        }),
    );
    renderWithQuery(
      <MeetingDialog open onOpenChange={() => {}} meeting={null} />,
    );
    await pasteAndParse();
    expect(await screen.findByRole("status")).toHaveTextContent(/reading/i);

    await userEvent.click(
      screen.getByRole("button", { name: "Cancel parsing" }),
    );
    expect(signal?.aborted).toBe(true);
    await waitFor(() =>
      expect(screen.getByRole("button", { name: "Parse" })).toBeInTheDocument(),
    );
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("blocks text over the limit before anything is sent", async () => {
    renderWithQuery(
      <MeetingDialog open onOpenChange={() => {}} meeting={null} />,
    );
    await userEvent.click(
      screen.getByRole("button", { name: /paste an agenda/i }),
    );
    const box = screen.getByLabelText("Paste an agenda");
    await userEvent.click(box);
    await userEvent.paste("x".repeat(10_001));
    expect(screen.getByRole("button", { name: "Parse" })).toBeDisabled();
    expect(parser.parseAgenda).not.toHaveBeenCalled();
  });
});
