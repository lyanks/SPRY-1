"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect } from "react";
import { useAuth } from "react-oidc-context";

import { authEnabled } from "@/lib/auth-config";

// Cognito sends the browser back here with ?code=...&state=.... The provider
// in the root layout exchanges the code for tokens as soon as it sees them;
// this page only waits for that and then goes home.
export default function CallbackPage() {
  return (
    <main className="grid min-h-screen place-items-center p-6">
      <div className="rounded-3xl bg-card p-8 text-center text-sm shadow-sm">
        {authEnabled ? <Finishing /> : <p>Sign-in is not configured.</p>}
      </div>
    </main>
  );
}

function Finishing() {
  const router = useRouter();
  const { isAuthenticated, error } = useAuth();

  useEffect(() => {
    if (isAuthenticated) router.replace("/");
  }, [isAuthenticated, router]);

  if (error) {
    return (
      <div role="alert" className="space-y-3">
        <p>Sign-in failed: {error.message}</p>
        <Link href="/login" className="font-medium underline">
          Try again
        </Link>
      </div>
    );
  }
  return <p>Signing you in…</p>;
}
