"use client";

import { useRouter } from "next/navigation";
import { useEffect, useRef } from "react";
import { useAuth } from "react-oidc-context";

import { authEnabled } from "@/lib/auth-config";

// The URL to hand in: it starts the sign-in from inside the app, so the state
// and PKCE verifier the library generates are stored before the redirect and
// can be matched when the browser comes back to /auth/callback.
export default function LoginPage() {
  return (
    <main className="grid min-h-screen place-items-center p-6">
      <div className="rounded-3xl bg-card p-8 text-center text-sm shadow-sm">
        {authEnabled ? (
          <Redirecting />
        ) : (
          <p>Sign-in is not configured for this build.</p>
        )}
      </div>
    </main>
  );
}

function Redirecting() {
  const router = useRouter();
  const { isLoading, isAuthenticated, error, signinRedirect } = useAuth();
  const started = useRef(false);

  useEffect(() => {
    if (isLoading || started.current) return;
    if (isAuthenticated) {
      router.replace("/");
      return;
    }
    if (error) return;
    started.current = true;
    void signinRedirect();
  }, [isLoading, isAuthenticated, error, signinRedirect, router]);

  if (error) return <p role="alert">Sign-in failed: {error.message}</p>;
  return <p>Redirecting to sign-in…</p>;
}
