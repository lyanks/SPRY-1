import type { Metadata } from "next";
import "@fontsource-variable/plus-jakarta-sans";

import { AuthProvider } from "@/components/auth-provider";
import { Providers } from "@/components/providers";
import { Toaster } from "@/components/ui/sonner";

import "./globals.css";

export const metadata: Metadata = {
  title: "Spry",
  description: "See where your week goes and protect time for deep work.",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className="h-full antialiased">
      {/* Extensions such as Grammarly stamp attributes on <body> before React
          hydrates; this silences that one-level mismatch only. */}
      <body className="min-h-full" suppressHydrationWarning>
        <Providers>
          <AuthProvider>
            {children}
            <Toaster />
          </AuthProvider>
        </Providers>
      </body>
    </html>
  );
}
