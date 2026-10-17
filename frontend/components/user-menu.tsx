"use client";

import { LogIn, LogOut } from "lucide-react";
import Link from "next/link";
import { useAuth } from "react-oidc-context";

import { Button } from "@/components/ui/button";
import { authEnabled, buildLogoutUrl } from "@/lib/auth-config";

/** Who is signed in, with Sign in / Sign out. Renders nothing when sign-in is not configured. */
export function UserMenu() {
  if (!authEnabled) return null;
  return <SignInState />;
}

function SignInState() {
  const auth = useAuth();

  if (auth.isLoading) {
    return <div className="h-8" aria-hidden />;
  }

  if (!auth.isAuthenticated) {
    return (
      <Button asChild variant="outline" size="sm">
        <Link href="/login">
          <LogIn data-icon="inline-start" />
          Sign in
        </Link>
      </Button>
    );
  }

  const email = auth.user?.profile.email ?? auth.user?.profile.sub;

  async function signOut() {
    await auth.removeUser();
    window.location.assign(buildLogoutUrl(window.location.origin));
  }

  return (
    <div className="flex items-center gap-3 text-sm">
      <span data-testid="signed-in-email" className="font-medium">
        {email}
      </span>
      <Button variant="outline" size="sm" onClick={signOut}>
        <LogOut data-icon="inline-start" />
        Sign out
      </Button>
    </div>
  );
}
