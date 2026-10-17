import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { RequireSignIn } from "@/components/require-sign-in";
import { GuestHome } from "@/components/guest-home";
import { Home } from "@/components/home";
import { demoInsights, demoMeetings } from "@/lib/demo";
import { SessionContext, type SessionStatus } from "@/lib/session";
import { dayKey, mondayOf, todayKey, weekDays } from "@/lib/time";

vi.mock("@/components/dashboard", () => ({
  Dashboard: () => <div>my own dashboard</div>,
}));

const as = (status: SessionStatus, ui: React.ReactElement) =>
  render(
    <SessionContext.Provider value={status}>{ui}</SessionContext.Provider>,
  );

describe("sample week", () => {
  const weekStart = mondayOf(todayKey());

  it("falls inside the current week and cannot be mistaken for real data", () => {
    const days = weekDays(weekStart);
    for (const m of demoMeetings(weekStart)) {
      expect(days).toContain(dayKey(m.starts_at));
      expect(m.id).toBeLessThan(0);
      expect(new Date(m.ends_at) > new Date(m.starts_at)).toBe(true);
    }
  });

  it("puts a 10:00 meeting at 10:00 in the working timezone", () => {
    const first = demoMeetings("2026-10-05")[0];
    expect(first.starts_at).toBe("2026-10-05T07:00:00.000Z"); // Kyiv is UTC+3
    expect(demoMeetings("2026-01-05")[0].starts_at).toBe(
      "2026-01-05T08:00:00.000Z", // UTC+2 in winter
    );
  });

  it("has numbers that add up", () => {
    const insights = demoInsights(weekStart);
    const meetings = demoMeetings(weekStart).filter(
      (m) => m.kind === "meeting",
    );
    expect(insights.meeting_count.value).toBe(meetings.length);
    expect(insights.meeting_minutes.change_pct).toBeLessThan(0);
  });
});

describe("what a guest sees", () => {
  it("lands on the sample week with a way to sign in, and nothing editable", () => {
    as("guest", <Home />);
    expect(screen.getByText(/a sample week/i)).toBeInTheDocument();
    expect(
      screen.getByRole("link", { name: /sign in or create an account/i }),
    ).toHaveAttribute("href", "/login");
    expect(screen.queryByText("my own dashboard")).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /add meeting/i })).toBeNull();
    // The sample's meetings are not clickable.
    for (const block of screen.getAllByRole("button")) {
      expect(block).toBeDisabled();
    }
  });

  it("is shown the dashboard once signed in", () => {
    as("user", <Home />);
    expect(screen.getByText("my own dashboard")).toBeInTheDocument();
  });

  it("keeps the old behaviour when sign-in is not configured", () => {
    as("disabled", <Home />);
    expect(screen.getByText("my own dashboard")).toBeInTheDocument();
  });

  it("shows nothing real while the session is still loading", () => {
    as("loading", <Home />);
    expect(screen.queryByText("my own dashboard")).not.toBeInTheDocument();
    expect(screen.queryByText(/a sample week/i)).not.toBeInTheDocument();
  });
});

describe("RequireSignIn", () => {
  it("asks guests to sign in instead of showing meetings", () => {
    as("guest", <RequireSignIn>secret meetings</RequireSignIn>);
    expect(screen.queryByText("secret meetings")).not.toBeInTheDocument();
    expect(screen.getByRole("link", { name: /sign in/i })).toHaveAttribute(
      "href",
      "/login",
    );
  });

  it("lets signed-in users through", () => {
    as("user", <RequireSignIn>secret meetings</RequireSignIn>);
    expect(screen.getByText("secret meetings")).toBeInTheDocument();
  });
});

describe("GuestHome", () => {
  it("renders on its own", () => {
    render(<GuestHome />);
    expect(
      screen.getByRole("region", { name: /week calendar/i }),
    ).toBeInTheDocument();
  });
});
