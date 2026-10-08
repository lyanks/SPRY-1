import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, type RenderOptions } from "@testing-library/react";
import type { ReactElement, ReactNode } from "react";

import type { Meeting } from "@/lib/api";

/** Render with a fresh QueryClient so tests never share cache state. */
export function renderWithQuery(ui: ReactElement, options?: RenderOptions) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });

  function Wrapper({ children }: { children: ReactNode }) {
    return (
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    );
  }

  return render(ui, { wrapper: Wrapper, ...options });
}

export function makeMeeting(overrides: Partial<Meeting> = {}): Meeting {
  return {
    id: 1,
    title: "Team sync",
    starts_at: "2026-10-07T07:00:00Z", // 10:00 in Kyiv
    ends_at: "2026-10-07T08:00:00Z",
    attendee_count: 4,
    kind: "meeting",
    agenda: null,
    has_agenda: false,
    ...overrides,
  };
}
