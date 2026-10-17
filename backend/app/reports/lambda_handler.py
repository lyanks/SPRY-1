"""report-builder: the backend image with a different handler.

Triggered by an SQS message (a command: "build this week"), or invoked directly
by a schedule or by hand. Every invocation logs which one it was.
"""

import json
import logging
import os
from datetime import datetime
from urllib.parse import quote
from zoneinfo import ZoneInfo

log = logging.getLogger()
log.setLevel(logging.INFO)


def detect_trigger(event: dict) -> str:
    records = event.get("Records") or []
    if records and records[0].get("eventSource") == "aws:sqs":
        return "sqs"
    if event.get("source") == "schedule":
        return "schedule"
    return "direct"


def payload_of(event: dict) -> dict:
    records = event.get("Records") or []
    if records and records[0].get("eventSource") == "aws:sqs":
        return json.loads(records[0]["body"] or "{}")
    return event


def _database_url_from_env() -> None:
    """On AWS the settings arrive as DB_* variables; build the URL before the app reads it."""
    if os.environ.get("DATABASE_URL") or not os.environ.get("DB_HOST"):
        return
    user = quote(os.environ.get("DB_USER", "spry"), safe="")
    password = quote(os.environ["DB_PASSWORD"], safe="")
    host, port = os.environ["DB_HOST"], os.environ.get("DB_PORT", "5432")
    name = os.environ.get("DB_NAME", "spry")
    query = "?ssl=require" if os.environ.get("DB_SSL") == "require" else ""
    os.environ["DATABASE_URL"] = (
        f"postgresql+asyncpg://{user}:{password}@{host}:{port}/{name}{query}"
    )


def handler(event, context=None, *, build=None, s3=None, now=None):
    """`build`, `s3` and `now` are injection points for tests."""
    _database_url_from_env()
    from app.reports.weekly import build_weekly_report, previous_week, report_key

    trigger = detect_trigger(event)
    payload = payload_of(event)
    clock = now or datetime.now(ZoneInfo("Europe/Kyiv"))
    week = payload.get("week") or previous_week(clock.date())
    log.info(
        "report-builder triggered",
        extra={"trigger": trigger, "week": week, "source": payload.get("source")},
    )
    # logging's `extra` does not reach plain-text CloudWatch lines, so say it in the message too.
    log.info("report-builder trigger=%s week=%s", trigger, week)

    body = (build or build_weekly_report)(week)
    key = report_key(week)
    if s3 is None:
        import boto3

        s3 = boto3.client("s3")
    s3.put_object(Bucket=os.environ["REPORTS_BUCKET"], Key=key, Body=body, ContentType="text/csv")
    log.info("report-builder wrote s3://%s/%s", os.environ["REPORTS_BUCKET"], key)
    return {"week": week, "key": key, "trigger": trigger}
