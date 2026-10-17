"use client";

import { CalendarDays, LayoutDashboard } from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";

import { UserMenu } from "@/components/user-menu";
import { useSession } from "@/lib/session";
import { cn } from "@/lib/utils";

const links = [
  { href: "/", label: "Dashboard", icon: LayoutDashboard },
  { href: "/meetings", label: "Meetings", icon: CalendarDays },
];

export function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const session = useSession();
  // Meetings are personal; the sample on the front page is all a guest has.
  const visible = session === "guest" ? links.slice(0, 1) : links;

  return (
    <div className="flex min-h-screen flex-col gap-3 p-3 md:flex-row md:gap-4 md:p-5">
      <aside className="flex shrink-0 items-center gap-2 rounded-3xl bg-violet p-2 text-white md:sticky md:top-5 md:h-[calc(100vh-2.5rem)] md:w-[4.25rem] md:flex-col md:py-4">
        <Link
          href="/"
          aria-label="Spry home"
          className="grid size-10 place-items-center rounded-2xl bg-lime text-lg font-extrabold text-ink"
        >
          S
        </Link>
        <nav aria-label="Main" className="flex gap-2 md:mt-6 md:flex-col">
          {visible.map(({ href, label, icon: Icon }) => {
            const active =
              href === "/" ? pathname === "/" : pathname.startsWith(href);
            return (
              <Link
                key={href}
                href={href}
                title={label}
                aria-label={label}
                aria-current={active ? "page" : undefined}
                className={cn(
                  "grid size-10 place-items-center rounded-2xl outline-none transition-colors focus-visible:ring-2 focus-visible:ring-lime",
                  active
                    ? "bg-white/20 text-lime"
                    : "text-white/70 hover:bg-white/10 hover:text-white",
                )}
              >
                <Icon className="size-5" />
              </Link>
            );
          })}
        </nav>
      </aside>
      <main className="min-w-0 flex-1">
        <header className="mb-3 flex min-h-8 justify-end">
          <UserMenu />
        </header>
        {children}
      </main>
    </div>
  );
}
