"use client";

import { Dashboard } from "@/components/dashboard";
import { GuestHome } from "@/components/guest-home";
import { Skeleton } from "@/components/ui/skeleton";
import { useSession } from "@/lib/session";

/** The front page: your own week when signed in, the sample for everyone else. */
export function Home() {
  const session = useSession();
  if (session === "loading") {
    return (
      <Skeleton className="h-[34rem] rounded-3xl bg-card/70" aria-busy="true" />
    );
  }
  if (session === "guest") return <GuestHome />;
  // "user", or "disabled" (no sign-in configured: local development).
  return <Dashboard />;
}
