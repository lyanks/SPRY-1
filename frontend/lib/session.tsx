"use client";

import { createContext, useContext } from "react";

/**
 * Who is looking at the site.
 *  - "disabled": sign-in is not configured in this build (local development);
 *    the app behaves as it did before accounts existed.
 *  - "loading":  the stored session is still being read.
 *  - "guest":    nobody is signed in.
 *  - "user":     signed in.
 */
export type SessionStatus = "disabled" | "loading" | "guest" | "user";

export const SessionContext = createContext<SessionStatus>("disabled");

export const useSession = () => useContext(SessionContext);
