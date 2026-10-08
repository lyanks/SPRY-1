from datetime import UTC, date, datetime, timedelta
from zoneinfo import ZoneInfo

from app.services import schedule as s


def at(h, m=0, day=5):
    return datetime(2026, 10, day, h, m, tzinfo=UTC)


WINDOW = (at(9), at(18))


def test_monday_of():
    assert s.monday_of(date(2026, 10, 8)) == date(2026, 10, 5)
    assert s.monday_of(date(2026, 10, 5)) == date(2026, 10, 5)
    assert s.monday_of(date(2026, 10, 11)) == date(2026, 10, 5)


def test_week_bounds_follow_local_midnight():
    start, end = s.week_bounds(date(2026, 10, 5), ZoneInfo("Europe/Kyiv"))
    assert start.utcoffset() == timedelta(hours=3)
    assert end - start == timedelta(days=7)


def test_free_gaps_ignores_outside_busy_and_merges_overlap():
    busy = [(at(7), at(9, 30)), (at(10), at(11)), (at(10, 30), at(12)), (at(20), at(21))]
    assert s.free_gaps(WINDOW, busy) == [(at(9, 30), at(10)), (at(12), at(18))]


def test_free_gaps_empty_and_full():
    assert s.free_gaps(WINDOW, []) == [WINDOW]
    assert s.free_gaps(WINDOW, [(at(8), at(19))]) == []


def test_deep_work_drops_gaps_shorter_than_minimum():
    assert s.deep_work_minutes([WINDOW], [(at(9), at(10)), (at(10, 30), at(18))], 60) == 0
    assert s.deep_work_minutes([WINDOW], [(at(9), at(10)), (at(11), at(18))], 60) == 60


def test_propose_slots_respects_not_before_and_min_length():
    busy = [(at(12), at(13))]
    got = s.propose_slots([WINDOW], busy, 120, not_before=at(10, 15))
    assert got == [(at(13), at(18))]  # 10:15-12:00 is 105 min, too short
    assert s.propose_slots([WINDOW], busy, 120, not_before=at(19)) == []


def test_pct_change():
    assert s.pct_change(60, 240) == -75.0
    assert s.pct_change(5, 0) is None
    assert s.pct_change(15, 10) == 50.0
