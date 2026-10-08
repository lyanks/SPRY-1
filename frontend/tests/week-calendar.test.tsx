import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

import { WeekCalendar, layoutDay } from "@/components/week-calendar";

import { makeMeeting } from "./utils";

describe("layoutDay", () => {
  it("puts overlapping meetings side by side", () => {
    const a = makeMeeting({
      id: 1,
      starts_at: "2026-10-07T07:00:00Z",
      ends_at: "2026-10-07T09:00:00Z",
    });
    const b = makeMeeting({
      id: 2,
      starts_at: "2026-10-07T08:00:00Z",
      ends_at: "2026-10-07T09:30:00Z",
    });
    const placed = layoutDay([b, a]);
    expect(placed.map((p) => [p.meeting.id, p.lane, p.lanes])).toEqual([
      [1, 0, 2],
      [2, 1, 2],
    ]);
  });

  it("gives back-to-back meetings the full width", () => {
    const a = makeMeeting({
      id: 1,
      starts_at: "2026-10-07T07:00:00Z",
      ends_at: "2026-10-07T08:00:00Z",
    });
    const b = makeMeeting({
      id: 2,
      starts_at: "2026-10-07T08:00:00Z",
      ends_at: "2026-10-07T09:00:00Z",
    });
    expect(layoutDay([a, b]).map((p) => p.lanes)).toEqual([1, 1]);
  });
});

describe("WeekCalendar", () => {
  const meetings = [
    makeMeeting({ id: 1, title: "Planning" }),
    makeMeeting({
      id: 2,
      title: "Focus time",
      kind: "focus",
      attendee_count: 1,
      starts_at: "2026-10-08T06:00:00Z",
      ends_at: "2026-10-08T08:00:00Z",
    }),
    makeMeeting({
      id: 3,
      title: "Ready",
      agenda: "Goals",
      has_agenda: true,
      starts_at: "2026-10-09T07:00:00Z",
      ends_at: "2026-10-09T08:00:00Z",
    }),
  ];

  it("places each meeting in its day column", () => {
    render(
      <WeekCalendar
        weekStart="2026-10-05"
        today="2026-10-07"
        meetings={meetings}
        onSelect={() => {}}
      />,
    );
    expect(
      within(screen.getByTestId("day-2026-10-07")).getByText("Planning"),
    ).toBeInTheDocument();
    expect(
      within(screen.getByTestId("day-2026-10-08")).getByText("Focus time"),
    ).toBeInTheDocument();
  });

  it("flags only meetings that have no agenda", () => {
    render(
      <WeekCalendar
        weekStart="2026-10-05"
        today="2026-10-07"
        meetings={meetings}
        onSelect={() => {}}
      />,
    );
    expect(
      screen.getByRole("button", { name: /Planning.*no agenda/ }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: /^Ready, / }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: /^Focus time, / }),
    ).toBeInTheDocument();
  });

  it("hides the weekend unless something is booked on it", () => {
    const { rerender } = render(
      <WeekCalendar
        weekStart="2026-10-05"
        today="2026-10-07"
        meetings={meetings}
        onSelect={() => {}}
      />,
    );
    expect(screen.queryByTestId("day-2026-10-10")).not.toBeInTheDocument();
    rerender(
      <WeekCalendar
        weekStart="2026-10-05"
        today="2026-10-07"
        meetings={[
          makeMeeting({
            id: 9,
            starts_at: "2026-10-10T07:00:00Z",
            ends_at: "2026-10-10T08:00:00Z",
          }),
        ]}
        onSelect={() => {}}
      />,
    );
    expect(screen.getByTestId("day-2026-10-10")).toBeInTheDocument();
  });

  it("reports the clicked meeting", async () => {
    const onSelect = vi.fn();
    render(
      <WeekCalendar
        weekStart="2026-10-05"
        today="2026-10-07"
        meetings={meetings}
        onSelect={onSelect}
      />,
    );
    await userEvent.click(
      screen.getByRole("button", { name: /^Focus time, / }),
    );
    expect(onSelect).toHaveBeenCalledWith(meetings[1]);
  });
});
