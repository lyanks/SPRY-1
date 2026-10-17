from datetime import datetime

from sqlalchemy import and_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.meeting import Meeting
from app.schemas.meeting import MeetingCreate, MeetingUpdate


async def list_meetings(
    session: AsyncSession,
    owner_id: str,
    *,
    starts_after: datetime | None = None,
    starts_before: datetime | None = None,
    kind: str | None = None,
) -> list[Meeting]:
    query = (
        select(Meeting)
        .where(Meeting.owner_id == owner_id)
        .order_by(Meeting.starts_at.asc(), Meeting.id.asc())
    )
    if starts_after is not None:
        query = query.where(Meeting.starts_at >= starts_after)
    if starts_before is not None:
        query = query.where(Meeting.starts_at < starts_before)
    if kind is not None:
        query = query.where(Meeting.kind == kind)
    return list((await session.execute(query)).scalars().all())


async def get_meeting(session: AsyncSession, owner_id: str, meeting_id: int) -> Meeting | None:
    """The meeting, only if it is on this person's calendar (someone else's is "not found")."""
    meeting = await session.get(Meeting, meeting_id)
    return meeting if meeting is not None and meeting.owner_id == owner_id else None


async def create_meeting(session: AsyncSession, owner_id: str, payload: MeetingCreate) -> Meeting:
    kind = payload.kind or ("meeting" if payload.attendee_count >= 2 else "other")
    meeting = Meeting(
        owner_id=owner_id,
        title=payload.title,
        starts_at=payload.starts_at,
        ends_at=payload.ends_at,
        attendee_count=payload.attendee_count,
        kind=kind,
        agenda=payload.agenda,
    )
    session.add(meeting)
    await session.flush()
    await session.refresh(meeting)
    return meeting


async def update_meeting(
    session: AsyncSession, meeting: Meeting, payload: MeetingUpdate
) -> Meeting:
    changes = {
        field: value
        for field, value in payload.model_dump(exclude_unset=True).items()
        if value is not None or field == "agenda"  # only agenda may be cleared with null
    }
    # Check the merged result before touching the row, so a bad value is never flushed.
    starts_at = changes.get("starts_at", meeting.starts_at)
    ends_at = changes.get("ends_at", meeting.ends_at)
    if ends_at <= starts_at:
        raise ValueError("ends_at must be after starts_at")
    for field, value in changes.items():
        setattr(meeting, field, value)
    await session.flush()
    await session.refresh(meeting)
    return meeting


async def delete_meeting(session: AsyncSession, meeting: Meeting) -> None:
    await session.delete(meeting)
    await session.flush()


async def overlapping(
    session: AsyncSession,
    owner_id: str,
    starts_at: datetime,
    ends_at: datetime,
    kinds: tuple[str, ...],
) -> list[Meeting]:
    result = await session.execute(
        select(Meeting).where(
            and_(
                Meeting.owner_id == owner_id,
                Meeting.starts_at < ends_at,
                Meeting.ends_at > starts_at,
                Meeting.kind.in_(kinds),
            )
        )
    )
    return list(result.scalars().all())
