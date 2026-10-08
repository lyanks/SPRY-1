import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

import { MeetingsTable } from "@/components/meetings-table";
import { MetricTiles } from "@/components/metric-tiles";
import { api } from "@/lib/api";

import { makeMeeting, renderWithQuery } from "./utils";

describe("MeetingsTable", () => {
  it("shows the empty state with a way forward", async () => {
    vi.spyOn(api, "listMeetings").mockResolvedValue([]);
    renderWithQuery(<MeetingsTable />);
    expect(await screen.findByText("No meetings yet")).toBeInTheDocument();
  });

  it("shows an error with a retry", async () => {
    vi.spyOn(api, "listMeetings").mockRejectedValue(new Error("down"));
    renderWithQuery(<MeetingsTable />);
    expect(
      await screen.findByText("Couldn’t load meetings."),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Try again" }),
    ).toBeInTheDocument();
  });

  it("deletes a meeting only after confirmation, then refreshes the list", async () => {
    const list = vi
      .spyOn(api, "listMeetings")
      .mockResolvedValueOnce([makeMeeting({ id: 5, title: "Budget review" })])
      .mockResolvedValue([]);
    const del = vi.spyOn(api, "deleteMeeting").mockResolvedValue(undefined);

    renderWithQuery(<MeetingsTable />);
    await userEvent.click(
      await screen.findByRole("button", { name: "Delete Budget review" }),
    );

    // The dialog asks first; nothing is deleted yet.
    expect(await screen.findByText("Delete this meeting?")).toBeInTheDocument();
    expect(del).not.toHaveBeenCalled();

    await userEvent.click(
      screen.getByRole("button", { name: "Delete meeting" }),
    );
    await waitFor(() => expect(del).toHaveBeenCalledWith(5));
    expect(await screen.findByText("No meetings yet")).toBeInTheDocument();
    expect(list).toHaveBeenCalledTimes(2);
  });

  it("keeps the meeting when deletion is cancelled", async () => {
    vi.spyOn(api, "listMeetings").mockResolvedValue([
      makeMeeting({ id: 5, title: "Budget review" }),
    ]);
    const del = vi.spyOn(api, "deleteMeeting").mockResolvedValue(undefined);

    renderWithQuery(<MeetingsTable />);
    await userEvent.click(
      await screen.findByRole("button", { name: "Delete Budget review" }),
    );
    await userEvent.click(
      await screen.findByRole("button", { name: "Keep meeting" }),
    );

    expect(del).not.toHaveBeenCalled();
    expect(screen.getByText("Budget review")).toBeInTheDocument();
  });
});

describe("MetricTiles", () => {
  const insights = {
    week_start: "2026-10-05",
    week_end: "2026-10-11",
    timezone: "Europe/Kyiv",
    meeting_minutes: { value: 150, previous: 300, change_pct: -50 },
    meeting_count: { value: 3, previous: 0, change_pct: null },
    deep_work_minutes: { value: 2400, previous: 2500, change_pct: -4 },
  };

  it("shows hours, counts and the week-over-week change", () => {
    renderWithQuery(<MetricTiles insights={insights} loading={false} />);
    expect(screen.getByText("2.5")).toBeInTheDocument();
    expect(screen.getByText("40")).toBeInTheDocument();
    expect(screen.getByText("50%")).toBeInTheDocument();
    expect(screen.getByText("Nothing to compare yet")).toBeInTheDocument();
  });
});
