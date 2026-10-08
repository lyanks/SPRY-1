import pytest
from httpx import AsyncClient

BASE = {
    "title": "Weekly Sprint Planning",
    "starts_at": "2026-10-08T10:00:00Z",
    "ends_at": "2026-10-08T10:45:00Z",
    "attendee_count": 6,
}


async def _create(client: AsyncClient, **override) -> dict:
    res = await client.post("/api/meetings", json={**BASE, **override})
    assert res.status_code == 201, res.text
    return res.json()


async def test_list_empty(client: AsyncClient):
    res = await client.get("/api/meetings")
    assert res.status_code == 200
    assert res.json() == []


async def test_create_derives_kind_and_lists(client: AsyncClient):
    team = await _create(client)
    solo = await _create(client, title="Solo", attendee_count=1)
    assert team["kind"] == "meeting"
    assert solo["kind"] == "other"
    assert team["has_agenda"] is False
    rows = (await client.get("/api/meetings")).json()
    assert [m["id"] for m in rows] == [team["id"], solo["id"]]


async def test_list_filters(client: AsyncClient):
    await _create(
        client, title="early", starts_at="2026-10-01T10:00:00Z", ends_at="2026-10-01T11:00:00Z"
    )
    await _create(client, title="late")
    res = await client.get("/api/meetings", params={"starts_after": "2026-10-05T00:00:00Z"})
    assert [m["title"] for m in res.json()] == ["late"]
    assert (await client.get("/api/meetings", params={"kind": "focus"})).json() == []


@pytest.mark.parametrize(
    "bad",
    [
        {"ends_at": "2026-10-08T10:00:00Z"},  # zero length
        {"ends_at": "2026-10-08T09:00:00Z"},  # ends before it starts
        {"title": ""},
        {"attendee_count": 0},
        {"kind": "party"},
    ],
)
async def test_create_rejects_invalid(client: AsyncClient, bad: dict):
    res = await client.post("/api/meetings", json={**BASE, **bad})
    assert res.status_code == 422


async def test_get_and_404(client: AsyncClient):
    m = await _create(client)
    assert (await client.get(f"/api/meetings/{m['id']}")).json()["title"] == BASE["title"]
    assert (await client.get("/api/meetings/99999")).status_code == 404


async def test_patch_edits_only_sent_fields(client: AsyncClient):
    m = await _create(client)
    res = await client.patch(f"/api/meetings/{m['id']}", json={"title": "Renamed"})
    assert res.status_code == 200
    body = res.json()
    assert body["title"] == "Renamed"
    assert body["attendee_count"] == 6
    assert body["starts_at"].startswith("2026-10-08T10:00")


async def test_patch_agenda_set_and_clear(client: AsyncClient):
    m = await _create(client)
    url = f"/api/meetings/{m['id']}"
    body = (await client.patch(url, json={"agenda": "1. Goals\n2. Risks"})).json()
    assert body["has_agenda"] is True
    body = (await client.patch(url, json={"agenda": None})).json()
    assert body["agenda"] is None
    assert body["has_agenda"] is False


async def test_patch_rejects_inverted_times(client: AsyncClient):
    m = await _create(client)
    # only one side is sent, so the merged result is what gets checked
    res = await client.patch(f"/api/meetings/{m['id']}", json={"ends_at": "2026-10-08T09:00:00Z"})
    assert res.status_code == 422
    assert (await client.patch("/api/meetings/99999", json={"title": "x"})).status_code == 404


async def test_delete(client: AsyncClient):
    keep = await _create(client, title="keep")
    gone = await _create(client, title="gone")
    res = await client.delete(f"/api/meetings/{gone['id']}")
    assert res.status_code == 204
    assert res.content == b""
    assert (await client.get(f"/api/meetings/{gone['id']}")).status_code == 404
    assert [m["id"] for m in (await client.get("/api/meetings")).json()] == [keep["id"]]
    assert (await client.delete(f"/api/meetings/{gone['id']}")).status_code == 404
