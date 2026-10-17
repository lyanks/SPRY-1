"use client";

import { AuthProvider as OidcProvider, useAuth } from "react-oidc-context";

import { authEnabled, buildOidcSettings } from "@/lib/auth-config";
import { SessionContext, type SessionStatus } from "@/lib/session";

/** Wraps the app in the OIDC provider, or does nothing when sign-in is not configured. */
export function AuthProvider({ children }: { children: React.ReactNode }) {
  if (!authEnabled) return <>{children}</>;

  // The provider renders no markup of its own, so the empty origin used while
  // the export is prerendered cannot cause a hydration mismatch.
  const origin = typeof window === "undefined" ? "" : window.location.origin;

  return (
    <OidcProvider
      {...buildOidcSettings(origin)}
      onSigninCallback={() => {
        // Drop ?code=...&state=... from the address bar once they are used.
        window.history.replaceState(
          {},
          document.title,
          window.location.pathname,
        );
      }}
    >
      <Session>{children}</Session>
    </OidcProvider>
  );
}

function Session({ children }: { children: React.ReactNode }) {
  const auth = useAuth();
  const status: SessionStatus = auth.isLoading
    ? "loading"
    : auth.isAuthenticated
      ? "user"
      : "guest";
  return (
    <SessionContext.Provider value={status}>{children}</SessionContext.Provider>
  );
}
