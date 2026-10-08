from datetime import date, datetime

from pydantic import BaseModel

from app.schemas.meeting import MeetingRead


class Metric(BaseModel):
    value: float
    previous: float
    # Percent change vs the previous week; None when there is nothing to compare to.
    change_pct: float | None


class WeekInsights(BaseModel):
    week_start: date
    week_end: date
    timezone: str
    meeting_minutes: Metric
    meeting_count: Metric
    deep_work_minutes: Metric


class Slot(BaseModel):
    starts_at: datetime
    ends_at: datetime
    minutes: int


class SlotProposal(BaseModel):
    slots: list[Slot]
    total_minutes: int


class SlotReserve(BaseModel):
    starts_at: datetime
    ends_at: datetime
    title: str = "Deep work (Spry)"


class AgendaReadiness(BaseModel):
    window_days: int
    upcoming: int
    without_agenda: int
    without_agenda_pct: float
    meetings: list[MeetingRead]
