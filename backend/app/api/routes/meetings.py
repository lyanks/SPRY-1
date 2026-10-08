from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, HTTPException, Query, Response, status

from app.db import SessionDep
from app.models.meeting import Meeting
from app.schemas.meeting import Kind, MeetingCreate, MeetingRead, MeetingUpdate
from app.services import meetings as svc

router = APIRouter(prefix="/meetings", tags=["meetings"])


async def _get_or_404(session: SessionDep, meeting_id: int) -> Meeting:
    meeting = await svc.get_meeting(session, meeting_id)
    if meeting is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Meeting not found")
    return meeting


@router.get("", response_model=list[MeetingRead], summary="List meetings, oldest first")
async def list_meetings(
    session: SessionDep,
    starts_after: Annotated[datetime | None, Query(description="Inclusive, ISO 8601")] = None,
    starts_before: Annotated[datetime | None, Query(description="Exclusive, ISO 8601")] = None,
    kind: Kind | None = None,
) -> list[MeetingRead]:
    rows = await svc.list_meetings(
        session, starts_after=starts_after, starts_before=starts_before, kind=kind
    )
    return [MeetingRead.model_validate(m) for m in rows]


@router.post(
    "", response_model=MeetingRead, status_code=status.HTTP_201_CREATED, summary="Create a meeting"
)
async def create_meeting(payload: MeetingCreate, session: SessionDep) -> MeetingRead:
    return MeetingRead.model_validate(await svc.create_meeting(session, payload))


@router.get("/{meeting_id}", response_model=MeetingRead, summary="Get one meeting")
async def get_meeting(meeting_id: int, session: SessionDep) -> MeetingRead:
    return MeetingRead.model_validate(await _get_or_404(session, meeting_id))


@router.patch("/{meeting_id}", response_model=MeetingRead, summary="Edit a meeting or its agenda")
async def update_meeting(
    meeting_id: int, payload: MeetingUpdate, session: SessionDep
) -> MeetingRead:
    meeting = await _get_or_404(session, meeting_id)
    try:
        meeting = await svc.update_meeting(session, meeting, payload)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail=str(exc)
        ) from exc
    return MeetingRead.model_validate(meeting)


@router.delete("/{meeting_id}", status_code=status.HTTP_204_NO_CONTENT, summary="Delete a meeting")
async def delete_meeting(meeting_id: int, session: SessionDep) -> Response:
    await svc.delete_meeting(session, await _get_or_404(session, meeting_id))
    return Response(status_code=status.HTTP_204_NO_CONTENT)
