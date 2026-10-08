import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_health(anon_client: AsyncClient):
    response = await anon_client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


@pytest.mark.asyncio
async def test_health_ready(anon_client: AsyncClient):
    response = await anon_client.get("/api/health/ready")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "database": "ok"}
