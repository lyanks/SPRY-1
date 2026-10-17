import json
from datetime import UTC, date, datetime, timedelta

import pytest

from app.models.meeting import Meeting
from app.reports import lambda_handler
from app.reports.weekly import (
    MeetingRow,
    build_report_async,
    parse_week,
    previous_week,
    render_csv,
    report_key,
)


def row(title: str, hours: float, day: int = 5, attendees: int = 3) -> MeetingRow:
    return MeetingRow(title, datetime(2026, 9, day, 9, tzinfo=UTC), hours, attendees)


def test_parse_week_gives_the_monday():
    assert parse_week("2026-W40") == date(2026, 9, 28)


@pytest.mark.parametrize("bad", ["2026-40", "W40", "2026-W4", "last week"])
def test_parse_week_rejects_garbage(bad):
    with pytest.raises(ValueError):
        parse_week(bad)


def test_previous_week_and_stable_key():
    assert previous_week(date(2026, 10, 5)) == "2026-W40"  # Monday of W41
    assert report_key("2026-W40") == "reports/2026-W40.csv"
    assert report_key("2026-W40") == report_key("2026-W40")  # idempotent name


def test_csv_totals_change_and_longest_five():
    current = [row(f"m{i}", hours=float(i)) for i in range(1, 8)]  # 1..7 h, 7 meetings, 28 h
    previous = [row("old", 2.0)]
    lines = render_csv("2026-W40", current, previous).decode().splitlines()
    assert "summary,meetings,7" in lines
    assert "summary,hours,28.0" in lines
    assert "summary,meetings_change,6" in lines
    assert "summary,hours_change,26.0" in lines
    longest = [line for line in lines if line.startswith("longest,") and "rank" not in line]
    assert len(longest) == 5
    assert longest[0].startswith("longest,1,m7,")


async def test_report_counts_only_meetings_of_that_week(session):
    monday = datetime(2026, 9, 28, 9, tzinfo=UTC)
    session.add_all(
        [
            Meeting(
                owner_id="u1",
                title="in week",
                starts_at=monday,
                ends_at=monday + timedelta(hours=2),
                attendee_count=4,
            ),
            Meeting(
                owner_id="u1",
                title="focus",
                starts_at=monday,
                ends_at=monday + timedelta(hours=3),
                kind="focus",
            ),
            Meeting(
                owner_id="u1",
                title="last week",
                starts_at=monday - timedelta(days=7),
                ends_at=monday - timedelta(days=7) + timedelta(hours=1),
            ),
            Meeting(
                owner_id="u1",
                title="next week",
                starts_at=monday + timedelta(days=7),
                ends_at=monday + timedelta(days=7, hours=1),
            ),
        ]
    )
    await session.flush()
    lines = (await build_report_async(session, "2026-W40")).decode().splitlines()
    assert "summary,meetings,1" in lines
    assert "summary,hours,2.0" in lines
    assert "summary,previous_meetings,1" in lines  # the focus block is not a meeting


class FakeS3:
    def __init__(self):
        self.puts = []

    def put_object(self, **kwargs):
        self.puts.append(kwargs)


def test_handler_sqs_message_names_the_week_and_the_trigger(monkeypatch, caplog):
    monkeypatch.setenv("REPORTS_BUCKET", "bucket")
    s3 = FakeS3()
    event = {
        "Records": [
            {"eventSource": "aws:sqs", "body": json.dumps({"week": "2026-W39", "source": "make"})}
        ]
    }
    with caplog.at_level("INFO"):
        result = lambda_handler.handler(event, build=lambda week: week.encode(), s3=s3)
    assert result == {"week": "2026-W39", "key": "reports/2026-W39.csv", "trigger": "sqs"}
    assert s3.puts[0]["Key"] == "reports/2026-W39.csv"
    assert "report-builder trigger=sqs week=2026-W39" in caplog.text


def test_handler_schedule_defaults_to_the_previous_week(monkeypatch):
    monkeypatch.setenv("REPORTS_BUCKET", "bucket")
    monday = datetime(2026, 10, 5, 7, tzinfo=UTC)
    result = lambda_handler.handler(
        {"source": "schedule"}, build=lambda week: b"x", s3=FakeS3(), now=monday
    )
    assert result["week"] == "2026-W40"
    assert result["trigger"] == "schedule"


def _sqs(body: dict) -> dict:
    return {"Records": [{"eventSource": "aws:sqs", "body": json.dumps(body)}]}


def test_schedule_message_from_sqs_is_logged_as_the_schedule(monkeypatch, caplog):
    monkeypatch.setenv("REPORTS_BUCKET", "bucket")
    monday = datetime(2026, 10, 5, 7, tzinfo=UTC)
    with caplog.at_level("INFO"):
        result = lambda_handler.handler(
            _sqs({"week": None, "source": "schedule"}),
            build=lambda week: b"x",
            s3=FakeS3(),
            now=monday,
        )
    assert result["trigger"] == "schedule"
    assert result["week"] == "2026-W40"
    assert "report-builder trigger=schedule week=2026-W40" in caplog.text


def test_fail_week_makes_only_that_week_fail(monkeypatch):
    monkeypatch.setenv("REPORTS_BUCKET", "bucket")
    monkeypatch.setenv("FAIL_WEEK", "2026-W39")
    event = _sqs({"week": "2026-W39", "source": "make"})
    with pytest.raises(RuntimeError):
        lambda_handler.handler(event, build=lambda week: b"x", s3=FakeS3())
    ok = lambda_handler.handler(
        _sqs({"week": "2026-W38", "source": "make"}), build=lambda week: b"x", s3=FakeS3()
    )
    assert ok["week"] == "2026-W38"
