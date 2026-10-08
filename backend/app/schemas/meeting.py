from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

Kind = Literal["meeting", "focus", "other"]


def _check_order(starts_at: datetime | None, ends_at: datetime | None) -> None:
    if starts_at and ends_at and ends_at <= starts_at:
        raise ValueError("ends_at must be after starts_at")


class MeetingCreate(BaseModel):
    title: str = Field(min_length=1, max_length=255)
    starts_at: datetime
    ends_at: datetime
    attendee_count: int = Field(default=1, ge=1, le=1000)
    # Omitted -> derived: 2+ attendees is a "meeting", otherwise "other" (FR-7).
    kind: Kind | None = None
    agenda: str | None = Field(default=None, max_length=10_000)

    @model_validator(mode="after")
    def _times(self):
        _check_order(self.starts_at, self.ends_at)
        return self


class MeetingUpdate(BaseModel):
    """PATCH body: send only the fields that change."""

    title: str | None = Field(default=None, min_length=1, max_length=255)
    starts_at: datetime | None = None
    ends_at: datetime | None = None
    attendee_count: int | None = Field(default=None, ge=1, le=1000)
    kind: Kind | None = None
    agenda: str | None = Field(default=None, max_length=10_000)

    @model_validator(mode="after")
    def _times(self):
        _check_order(self.starts_at, self.ends_at)
        return self


class MeetingRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    title: str
    starts_at: datetime
    ends_at: datetime
    attendee_count: int
    kind: Kind
    agenda: str | None
    has_agenda: bool = False

    @model_validator(mode="after")
    def _flag(self):
        self.has_agenda = bool(self.agenda and self.agenda.strip())
        return self
