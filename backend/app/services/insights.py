from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings
from app.models.meeting import Meeting
from app.schemas.insights import AgendaReadiness, Metric, Slot, SlotProposal, WeekInsights
from app.schemas.meeting import MeetingRead
from app.services import schedule


def _tz(settings: Settings) -> ZoneInfo:
    return ZoneInfo(settings.work_timezone)


def _metric(current: float, previous: float) -> Metric:
    return Metric(
        value=current, previous=previous, change_pct=schedule.pct_change(current, previous)
    )


async def _events(
    session: AsyncSession, start: datetime, end: datetime, kinds: tuple[str, ...]
) -> list[Meeting]:
    """Events that overlap [start, end)."""
    result = await session.execute(
        select(Meeting).where(
            Meeting.starts_at < end, Meeting.ends_at > start, Meeting.kind.in_(kinds)
        )
    )
    return list(result.scalars().all())


async def _week(
    session: AsyncSession, settings: Settings, week_start: date
) -> tuple[int, int, int]:
    """(meeting minutes, meeting count, deep-work minutes) for one ISO week."""
    tz = _tz(settings)
    start, end = schedule.week_bounds(week_start, tz)
    meetings = await _events(session, start, end, ("meeting",))
    # A meeting counts in the week it starts in; busy time uses every overlapping one.
    in_week = [m for m in meetings if start <= m.starts_at < end]
    meeting_minutes = sum(schedule.minutes((m.starts_at, m.ends_at)) for m in in_week)
    windows = schedule.working_windows(
        week_start, tz, settings.work_start_hour, settings.work_end_hour
    )
    busy = [(m.starts_at, m.ends_at) for m in meetings]
    deep = schedule.deep_work_minutes(windows, busy, settings.deep_work_min_minutes)
    return meeting_minutes, len(in_week), deep


async def week_insights(session: AsyncSession, settings: Settings, week_of: date) -> WeekInsights:
    week_start = schedule.monday_of(week_of)
    cur = await _week(session, settings, week_start)
    prev = await _week(session, settings, week_start - timedelta(days=7))
    return WeekInsights(
        week_start=week_start,
        week_end=week_start + timedelta(days=6),
        timezone=settings.work_timezone,
        meeting_minutes=_metric(cur[0], prev[0]),
        meeting_count=_metric(cur[1], prev[1]),
        deep_work_minutes=_metric(cur[2], prev[2]),
    )


async def propose_deep_work(
    session: AsyncSession, settings: Settings, now: datetime
) -> SlotProposal:
    """Free slots in the current and the next week (FR-14)."""
    tz = _tz(settings)
    this_monday = schedule.monday_of(now.astimezone(tz).date())
    slots: list[Slot] = []
    for week_start in (this_monday, this_monday + timedelta(days=7)):
        start, end = schedule.week_bounds(week_start, tz)
        busy_events = await _events(session, start, end, ("meeting", "focus"))
        windows = schedule.working_windows(
            week_start, tz, settings.work_start_hour, settings.work_end_hour
        )
        for s, e in schedule.propose_slots(
            windows,
            [(m.starts_at, m.ends_at) for m in busy_events],
            settings.deep_work_block_minutes,
            not_before=now,
        ):
            # Gaps that begin where a stored event ends are UTC; show everything in work time.
            s, e = s.astimezone(tz), e.astimezone(tz)
            slots.append(Slot(starts_at=s, ends_at=e, minutes=schedule.minutes((s, e))))
    return SlotProposal(slots=slots, total_minutes=sum(s.minutes for s in slots))


async def agenda_readiness(
    session: AsyncSession, now: datetime, window_days: int = 7
) -> AgendaReadiness:
    """Share of meetings in the next `window_days` that have no agenda (FR-17, FR-18)."""
    end = now + timedelta(days=window_days)
    result = await session.execute(
        select(Meeting)
        .where(Meeting.kind == "meeting", Meeting.starts_at >= now, Meeting.starts_at < end)
        .order_by(Meeting.starts_at.asc())
    )
    upcoming = list(result.scalars().all())
    missing = [m for m in upcoming if not (m.agenda and m.agenda.strip())]
    pct = round(len(missing) / len(upcoming) * 100, 1) if upcoming else 0.0
    return AgendaReadiness(
        window_days=window_days,
        upcoming=len(upcoming),
        without_agenda=len(missing),
        without_agenda_pct=pct,
        meetings=[MeetingRead.model_validate(m) for m in missing],
    )
