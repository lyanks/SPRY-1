"""Each person's calendar is theirs alone."""

from httpx import AsyncClient

BODY = {
    "title": "1:1",
    "starts_at": "2026-10-07T07:00:00Z",
    "ends_at": "2026-10-07T08:00:00Z",
    "attendee_count": 2,
}


async def _create(client: AsyncClient, **override) -> dict:
    res = await client.post("/api/meetings", json={**BODY, **override})
    assert res.status_code == 201, res.text
    return res.json()


async def test_lists_show_only_my_meetings(client: AsyncClient, other_client: AsyncClient):
    mine = await _create(client, title="Ada's")
    await _create(other_client, title="Grace's")
    assert [m["id"] for m in (await client.get("/api/meetings")).json()] == [mine["id"]]
    assert [m["title"] for m in (await other_client.get("/api/meetings")).json()] == ["Grace's"]


async def test_someone_elses_meeting_is_not_found(client: AsyncClient, other_client: AsyncClient):
    theirs = await _create(other_client)
    url = f"/api/meetings/{theirs['id']}"
    assert (await client.get(url)).status_code == 404
    assert (await client.patch(url, json={"title": "mine now"})).status_code == 404
    assert (await client.delete(url)).status_code == 404
    # ...and it is untouched.
    assert (await other_client.get(url)).json()["title"] == "1:1"


async def test_insights_count_only_my_meetings(client: AsyncClient, other_client: AsyncClient):
    await _create(other_client)
    week = (await client.get("/api/insights/week")).json()
    assert week["meeting_count"]["value"] == 0
    assert (await other_client.get("/api/insights/week")).json()["meeting_count"]["value"] == 1


async def test_agenda_readiness_ignores_other_calendars(
    client: AsyncClient, other_client: AsyncClient
):
    await _create(other_client, starts_at="2026-10-08T07:00:00Z", ends_at="2026-10-08T08:00:00Z")
    assert (await client.get("/api/agenda/readiness")).json()["upcoming"] == 0


async def test_my_busy_time_is_not_blocked_by_someone_elses(
    client: AsyncClient, other_client: AsyncClient
):
    await _create(other_client)
    slot = {"title": "Focus", "starts_at": BODY["starts_at"], "ends_at": BODY["ends_at"]}
    assert (await client.post("/api/deep-work/reserve", json=slot)).status_code == 201
