"""Pure scheduling maths: no database, no HTTP, no clock.

Everything works on (start, end) pairs of timezone-aware datetimes. Adding a new
insight means adding a function here and one query in services/insights.py.
"""

from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

Interval = tuple[datetime, datetime]


def monday_of(day: date) -> date:
    return day - timedelta(days=day.weekday())


def week_bounds(week_start: date, tz: ZoneInfo) -> Interval:
    """[Monday 00:00, next Monday 00:00) in the working timezone."""
    start = datetime.combine(week_start, time.min, tzinfo=tz)
    end = datetime.combine(week_start + timedelta(days=7), time.min, tzinfo=tz)
    return start, end


def working_windows(
    week_start: date, tz: ZoneInfo, start_hour: int, end_hour: int
) -> list[Interval]:
    """Monday to Friday working hours of one week."""
    windows = []
    for offset in range(5):
        day = week_start + timedelta(days=offset)
        windows.append(
            (
                datetime.combine(day, time(start_hour), tzinfo=tz),
                datetime.combine(day, time(end_hour), tzinfo=tz),
            )
        )
    return windows


def merge(intervals: list[Interval]) -> list[Interval]:
    merged: list[Interval] = []
    for start, end in sorted(intervals):
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))
    return merged


def free_gaps(window: Interval, busy: list[Interval]) -> list[Interval]:
    """What is left of one window after removing the busy intervals."""
    gaps: list[Interval] = []
    cursor, window_end = window
    for start, end in merge(busy):
        if end <= cursor or start >= window_end:
            continue
        if start > cursor:
            gaps.append((cursor, start))
        cursor = max(cursor, end)
    if cursor < window_end:
        gaps.append((cursor, window_end))
    return gaps


def minutes(interval: Interval) -> int:
    return int((interval[1] - interval[0]).total_seconds() // 60)


def deep_work_minutes(windows: list[Interval], busy: list[Interval], min_minutes: int) -> int:
    """Contiguous free time of at least `min_minutes` inside working hours (FR-9)."""
    total = 0
    for window in windows:
        for gap in free_gaps(window, busy):
            if minutes(gap) >= min_minutes:
                total += minutes(gap)
    return total


def propose_slots(
    windows: list[Interval], busy: list[Interval], min_minutes: int, not_before: datetime
) -> list[Interval]:
    """Free slots of at least `min_minutes`, none starting before `not_before` (FR-14)."""
    slots: list[Interval] = []
    for window in windows:
        for start, end in free_gaps(window, busy):
            start = max(start, not_before)
            if end - start >= timedelta(minutes=min_minutes):
                slots.append((start, end))
    return slots


def pct_change(current: float, previous: float) -> float | None:
    if previous == 0:
        return None
    return round((current - previous) / previous * 100, 1)
