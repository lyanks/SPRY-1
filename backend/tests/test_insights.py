from httpx import AsyncClient


async def _meeting(client: AsyncClient, start: str, end: str, **extra):
    payload = {"title": "m", "starts_at": start, "ends_at": end, "attendee_count": 4, **extra}
    res = await client.post("/api/meetings", json=payload)
    assert res.status_code == 201, res.text
    return res.json()


async def test_week_insights_with_week_over_week_change(client: AsyncClient):
    # Kyiv is UTC+3 this week, so 07:00Z is 10:00 local.
    await _meeting(client, "2026-10-05T07:00:00Z", "2026-10-05T08:00:00Z")  # this week, 60 min
    await _meeting(client, "2026-09-28T07:00:00Z", "2026-09-28T09:00:00Z")  # last week, 120 min
    await _meeting(client, "2026-09-29T07:00:00Z", "2026-09-29T09:00:00Z")  # last week, 120 min
    await _meeting(client, "2026-10-06T07:00:00Z", "2026-10-06T08:00:00Z", attendee_count=1)

    body = (await client.get("/api/insights/week")).json()
    assert body["week_start"] == "2026-10-05"
    assert body["week_end"] == "2026-10-11"
    assert body["meeting_minutes"] == {"value": 60.0, "previous": 240.0, "change_pct": -75.0}
    assert body["meeting_count"] == {"value": 1.0, "previous": 2.0, "change_pct": -50.0}
    # 5 working days x 9 h = 2700 min, minus the one booked hour.
    assert body["deep_work_minutes"]["value"] == 2640.0
    # Last week: two days each lose 2 h, the rest stays contiguous.
    assert body["deep_work_minutes"]["previous"] == 2700.0 - 240.0


async def test_week_of_selects_another_week(client: AsyncClient):
    await _meeting(client, "2026-09-28T07:00:00Z", "2026-09-28T09:00:00Z")
    body = (await client.get("/api/insights/week", params={"week_of": "2026-09-30"})).json()
    assert body["week_start"] == "2026-09-28"
    assert body["meeting_minutes"]["value"] == 120.0
    assert body["meeting_minutes"]["change_pct"] is None  # nothing the week before


async def test_slots_skip_the_past_and_booked_time(client: AsyncClient):
    # "now" is Wed 09:00 local. Wed 10:00-12:00 local is booked, so 09:00-10:00 is too short.
    await _meeting(client, "2026-10-07T07:00:00Z", "2026-10-07T09:00:00Z")
    body = (await client.get("/api/deep-work/slots")).json()
    first = body["slots"][0]
    assert first["starts_at"].startswith("2026-10-07T12:00:00+03:00")
    assert first["minutes"] == 360
    # Wed 360 + Thu 540 + Fri 540 + five full days next week
    assert body["total_minutes"] == 360 + 540 + 540 + 5 * 540
    assert len(body["slots"]) == 1 + 2 + 5


async def test_reserve_creates_focus_block_and_prevents_double_booking(client: AsyncClient):
    slot = {"starts_at": "2026-10-08T06:00:00Z", "ends_at": "2026-10-08T08:00:00Z"}  # 09-11 local
    res = await client.post("/api/deep-work/reserve", json=slot)
    assert res.status_code == 201
    block = res.json()
    assert block["kind"] == "focus"
    assert block["title"] == "Deep work (Spry)"

    clash = await client.post(
        "/api/deep-work/reserve",
        json={"starts_at": "2026-10-08T07:00:00Z", "ends_at": "2026-10-08T09:00:00Z"},
    )
    assert clash.status_code == 409

    # The booked time is no longer offered: Thursday now starts at 11:00 local.
    slots = (await client.get("/api/deep-work/slots")).json()["slots"]
    thursday = [s for s in slots if s["starts_at"].startswith("2026-10-08")]
    assert [s["starts_at"][:16] for s in thursday] == ["2026-10-08T11:00"]

    # Deleting the block frees the time again.
    assert (await client.delete(f"/api/meetings/{block['id']}")).status_code == 204
    assert (await client.post("/api/deep-work/reserve", json=slot)).status_code == 201


async def test_reserve_rejects_inverted_times(client: AsyncClient):
    res = await client.post(
        "/api/deep-work/reserve",
        json={"starts_at": "2026-10-08T08:00:00Z", "ends_at": "2026-10-08T06:00:00Z"},
    )
    assert res.status_code == 422


async def test_agenda_readiness(client: AsyncClient):
    await _meeting(client, "2026-10-08T07:00:00Z", "2026-10-08T08:00:00Z", title="no agenda 1")
    await _meeting(
        client, "2026-10-09T07:00:00Z", "2026-10-09T08:00:00Z", title="blank agenda", agenda="   "
    )
    await _meeting(
        client, "2026-10-09T09:00:00Z", "2026-10-09T10:00:00Z", title="ready", agenda="Goals"
    )
    await _meeting(client, "2026-10-20T07:00:00Z", "2026-10-20T08:00:00Z", title="too far away")
    await _meeting(
        client, "2026-10-08T11:00:00Z", "2026-10-08T12:00:00Z", title="solo", attendee_count=1
    )
    await _meeting(client, "2026-10-06T07:00:00Z", "2026-10-06T08:00:00Z", title="already past")

    body = (await client.get("/api/agenda/readiness")).json()
    assert body["upcoming"] == 3
    assert body["without_agenda"] == 2
    assert body["without_agenda_pct"] == 66.7
    assert [m["title"] for m in body["meetings"]] == ["no agenda 1", "blank agenda"]


async def test_agenda_readiness_with_nothing_upcoming(client: AsyncClient):
    body = (await client.get("/api/agenda/readiness")).json()
    assert body == {
        "window_days": 7,
        "upcoming": 0,
        "without_agenda": 0,
        "without_agenda_pct": 0.0,
        "meetings": [],
    }
