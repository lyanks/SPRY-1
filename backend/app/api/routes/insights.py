from datetime import date
from typing import Annotated
from zoneinfo import ZoneInfo

from fastapi import APIRouter, HTTPException, Query, status

from app.clock import NowDep
from app.config import get_settings
from app.db import SessionDep
from app.schemas.insights import AgendaReadiness, SlotProposal, SlotReserve, WeekInsights
from app.schemas.meeting import MeetingCreate, MeetingRead
from app.services import insights as svc
from app.services import meetings as meetings_svc

router = APIRouter(tags=["insights"])


@router.get("/insights/week", response_model=WeekInsights, summary="Weekly meeting load")
async def week_insights(
    session: SessionDep,
    now: NowDep,
    week_of: Annotated[
        date | None, Query(description="Any date inside the week; default: this week")
    ] = None,
) -> WeekInsights:
    settings = get_settings()
    if week_of is None:
        week_of = now.astimezone(ZoneInfo(settings.work_timezone)).date()
    return await svc.week_insights(session, settings, week_of)


@router.get("/agenda/readiness", response_model=AgendaReadiness, summary="Meetings without agenda")
async def agenda_readiness(session: SessionDep, now: NowDep) -> AgendaReadiness:
    return await svc.agenda_readiness(session, now)


@router.get("/deep-work/slots", response_model=SlotProposal, summary="Propose free focus slots")
async def deep_work_slots(session: SessionDep, now: NowDep) -> SlotProposal:
    return await svc.propose_deep_work(session, get_settings(), now)


@router.post(
    "/deep-work/reserve",
    response_model=MeetingRead,
    status_code=status.HTTP_201_CREATED,
    summary="Reserve a focus block",
)
async def reserve_deep_work(payload: SlotReserve, session: SessionDep) -> MeetingRead:
    if payload.ends_at <= payload.starts_at:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT, "ends_at must be after starts_at"
        )
    clash = await meetings_svc.overlapping(
        session, payload.starts_at, payload.ends_at, ("meeting", "focus")
    )
    if clash:
        raise HTTPException(status.HTTP_409_CONFLICT, f"Slot overlaps meeting #{clash[0].id}")
    meeting = await meetings_svc.create_meeting(
        session,
        MeetingCreate(
            title=payload.title,
            starts_at=payload.starts_at,
            ends_at=payload.ends_at,
            attendee_count=1,
            kind="focus",
        ),
    )
    return MeetingRead.model_validate(meeting)
