from datetime import UTC, datetime
from typing import Annotated

from fastapi import Depends


def get_now() -> datetime:
    """Current time as a dependency, so tests can pin it."""
    return datetime.now(UTC)


NowDep = Annotated[datetime, Depends(get_now)]
