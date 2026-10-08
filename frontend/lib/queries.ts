"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { api, type MeetingPayload } from "@/lib/api";
import { weekFetchRange } from "@/lib/time";

export const useWeekMeetings = (weekStart: string) =>
  useQuery({
    queryKey: ["meetings", weekStart],
    queryFn: () => api.listMeetings(weekFetchRange(weekStart)),
  });

export const useAllMeetings = () =>
  useQuery({
    queryKey: ["meetings", "all"],
    queryFn: () => api.listMeetings(),
  });

export const useWeekInsights = (weekStart: string) =>
  useQuery({
    queryKey: ["insights", weekStart],
    queryFn: () => api.weekInsights(weekStart),
  });

export const useAgendaReadiness = () =>
  useQuery({ queryKey: ["readiness"], queryFn: () => api.agendaReadiness() });

export const useDeepWorkSlots = () =>
  useQuery({ queryKey: ["slots"], queryFn: () => api.deepWorkSlots() });

/** Every number on screen derives from the meetings, so any change refreshes all of it. */
function useRefreshAll() {
  const client = useQueryClient();
  return () =>
    Promise.all(
      ["meetings", "insights", "readiness", "slots"].map((key) =>
        client.invalidateQueries({ queryKey: [key] }),
      ),
    );
}

export function useCreateMeeting() {
  const refresh = useRefreshAll();
  return useMutation({
    mutationFn: (payload: MeetingPayload) => api.createMeeting(payload),
    onSuccess: refresh,
  });
}

export function useUpdateMeeting() {
  const refresh = useRefreshAll();
  return useMutation({
    mutationFn: ({
      id,
      payload,
    }: {
      id: number;
      payload: Partial<MeetingPayload>;
    }) => api.updateMeeting(id, payload),
    onSuccess: refresh,
  });
}

export function useDeleteMeeting() {
  const refresh = useRefreshAll();
  return useMutation({
    mutationFn: (id: number) => api.deleteMeeting(id),
    onSuccess: refresh,
  });
}

export function useReserveDeepWork() {
  const refresh = useRefreshAll();
  return useMutation({
    mutationFn: (slot: { starts_at: string; ends_at: string }) =>
      api.reserveDeepWork(slot),
    onSuccess: refresh,
  });
}
