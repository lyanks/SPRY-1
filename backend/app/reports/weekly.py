"""The weekly meetings report.

`build_weekly_report(week)` is a plain function: no AWS in it. The week is a
parameter (never "last week" inside), and the file name derived from it
(`reports/<week>.csv`) is the same every time, so running it twice for one week
overwrites one file instead of creating two - which is what makes "at least
once" delivery harmless.
"""

import asyncio
import csv
import io
import re
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from app.config import get_settings
from app.models.meeting import Meeting
from app.services.schedule import week_bounds

_WEEK = re.compile(r"^(\d{4})-W(\d{2})$")
LONGEST = 5


@dataclass(frozen=True)
class MeetingRow:
    title: str
    starts_at: datetime
    hours: float
    attendees: int


def parse_week(week: str) -> date:
    """'2026-W40' -> the Monday of that ISO week."""
    match = _WEEK.match(week)
    if not match:
        raise ValueError(f"week must look like 2026-W40, got {week!r}")
    return date.fromisocalendar(int(match[1]), int(match[2]), 1)


def week_label(day: date) -> str:
    year, number, _ = day.isocalendar()
    return f"{year}-W{number:02d}"


def previous_week(today: date) -> str:
    """The ISO week before the one `today` falls in."""
    return week_label(today - timedelta(days=7))


def report_key(week: str) -> str:
    parse_week(week)
    return f"reports/{week}.csv"


def summarize(rows: list[MeetingRow]) -> tuple[int, float]:
    return len(rows), round(sum(row.hours for row in rows), 2)


def render_csv(week: str, current: list[MeetingRow], previous: list[MeetingRow]) -> bytes:
    """Pure: rows in, CSV bytes out."""
    count, hours = summarize(current)
    prev_count, prev_hours = summarize(previous)

    out = io.StringIO()
    writer = csv.writer(out, lineterminator="\n")
    writer.writerow(["section", "name", "value"])
    writer.writerow(["summary", "week", week])
    writer.writerow(["summary", "meetings", count])
    writer.writerow(["summary", "hours", hours])
    writer.writerow(["summary", "previous_meetings", prev_count])
    writer.writerow(["summary", "previous_hours", prev_hours])
    writer.writerow(["summary", "meetings_change", count - prev_count])
    writer.writerow(["summary", "hours_change", round(hours - prev_hours, 2)])
    writer.writerow([])
    writer.writerow(["longest", "rank", "title", "starts_at", "hours", "attendees"])
    longest = sorted(current, key=lambda r: (-r.hours, r.starts_at, r.title))[:LONGEST]
    for rank, row in enumerate(longest, start=1):
        writer.writerow(
            [
                "longest",
                rank,
                row.title,
                row.starts_at.isoformat(),
                round(row.hours, 2),
                row.attendees,
            ]
        )
    return out.getvalue().encode("utf-8")


async def fetch_rows(session: AsyncSession, monday: date, tz: ZoneInfo) -> list[MeetingRow]:
    start, end = week_bounds(monday, tz)
    result = await session.scalars(
        select(Meeting)
        .where(Meeting.kind == "meeting", Meeting.starts_at >= start, Meeting.starts_at < end)
        .order_by(Meeting.starts_at)
    )
    return [
        MeetingRow(
            title=m.title,
            starts_at=m.starts_at.astimezone(tz),
            hours=(m.ends_at - m.starts_at).total_seconds() / 3600,
            attendees=m.attendee_count,
        )
        for m in result.all()
    ]


async def build_report_async(session: AsyncSession, week: str) -> bytes:
    tz = ZoneInfo(get_settings().work_timezone)
    monday = parse_week(week)
    current = await fetch_rows(session, monday, tz)
    previous = await fetch_rows(session, monday - timedelta(days=7), tz)
    return render_csv(week, current, previous)


async def _build(week: str) -> bytes:
    # A Lambda runs one invocation at a time and may be frozen between them:
    # no pool, and the engine is closed before returning.
    engine = create_async_engine(get_settings().database_url, poolclass=NullPool)
    try:
        async with async_sessionmaker(engine, expire_on_commit=False)() as session:
            return await build_report_async(session, week)
    finally:
        await engine.dispose()


def build_weekly_report(week: str) -> bytes:
    """Query the meetings of one ISO week (e.g. "2026-W40") and return the CSV."""
    return asyncio.run(_build(week))
