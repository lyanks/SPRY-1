"use client";

import { LogIn } from "lucide-react";
import Link from "next/link";

import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { useSession } from "@/lib/session";

/** Shows its children to signed-in users only; everyone else is asked to sign in. */
export function RequireSignIn({ children }: { children: React.ReactNode }) {
  const session = useSession();
  if (session === "loading") {
    return (
      <Skeleton className="h-64 rounded-3xl bg-card/70" aria-busy="true" />
    );
  }
  if (session === "guest") {
    return (
      <div className="rounded-3xl bg-card p-8 text-center">
        <h1 className="text-2xl font-bold tracking-tight text-ink">
          Sign in to see your meetings
        </h1>
        <p className="mx-auto mt-2 max-w-md text-sm text-muted-foreground">
          Every calendar in Spry belongs to one person. Sign in, or create an
          account, to view and edit yours.
        </p>
        <Button asChild className="mt-5">
          <Link href="/login">
            <LogIn data-icon="inline-start" />
            Sign in
          </Link>
        </Button>
      </div>
    );
  }
  return <>{children}</>;
}
