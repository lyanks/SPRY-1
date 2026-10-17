import { MeetingsTable } from "@/components/meetings-table";
import { RequireSignIn } from "@/components/require-sign-in";

export const metadata = { title: "Meetings · Spry" };

export default function MeetingsPage() {
  return (
    <RequireSignIn>
      <MeetingsTable />
    </RequireSignIn>
  );
}
