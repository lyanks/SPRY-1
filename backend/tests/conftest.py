import os
from collections.abc import AsyncIterator
from datetime import UTC, datetime

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool


def _test_database_url() -> str:
    explicit = os.environ.get("TEST_DATABASE_URL")
    if explicit:
        return explicit

    runtime = os.environ.get("DATABASE_URL", "postgresql+asyncpg://spry:spry@localhost:5432/spry")
    base, _, database = runtime.rpartition("/")
    return f"{base}/{database}_test"


# Wednesday 2026-10-07 09:00 in Kyiv (UTC+3), inside the week of Monday 2026-10-05.
NOW = datetime(2026, 10, 7, 6, 0, tzinfo=UTC)

os.environ["APP_ENV"] = "test"
os.environ["DATABASE_URL"] = _test_database_url()

from app.clock import get_now  # noqa: E402
from app.db import Base, get_session  # noqa: E402
from app.main import create_app  # noqa: E402


async def _ensure_test_database(url: str) -> None:
    from sqlalchemy import text

    database = url.rsplit("/", 1)[-1]
    admin_url = url.rsplit("/", 1)[0] + "/postgres"
    admin = create_async_engine(admin_url, poolclass=NullPool, isolation_level="AUTOCOMMIT")
    try:
        async with admin.connect() as conn:
            exists = await conn.scalar(
                text("SELECT 1 FROM pg_database WHERE datname = :name"), {"name": database}
            )
            if not exists:
                await conn.execute(text(f'CREATE DATABASE "{database}"'))
    except Exception:
        pass
    finally:
        await admin.dispose()


@pytest.fixture(scope="session")
async def engine() -> AsyncIterator:
    url = os.environ["DATABASE_URL"]
    await _ensure_test_database(url)
    engine = create_async_engine(url, poolclass=NullPool)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    await engine.dispose()


@pytest.fixture
async def session(engine) -> AsyncIterator[AsyncSession]:
    connection = await engine.connect()
    transaction = await connection.begin()
    factory = async_sessionmaker(bind=connection, expire_on_commit=False, class_=AsyncSession)
    async with factory() as session:
        yield session
    await transaction.rollback()
    await connection.close()


@pytest.fixture
async def anon_client(session: AsyncSession) -> AsyncIterator[AsyncClient]:
    app = create_app()

    async def _override() -> AsyncIterator[AsyncSession]:
        yield session

    app.dependency_overrides[get_session] = _override
    app.dependency_overrides[get_now] = lambda: NOW
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client
    app.dependency_overrides.clear()


@pytest.fixture
async def client(anon_client: AsyncClient) -> AsyncClient:
    return anon_client
