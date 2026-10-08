"""meetings: kind, agenda, updated_at, sanity checks

Revision ID: 0003
Revises: 0002
Create Date: 2026-10-08

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0003"
down_revision: str | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "meetings", sa.Column("kind", sa.String(10), server_default="meeting", nullable=False)
    )
    op.add_column("meetings", sa.Column("agenda", sa.Text(), nullable=True))
    op.add_column(
        "meetings",
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
    )
    # Rows created before this revision may be 1-person entries: not meetings (FR-7).
    op.execute("UPDATE meetings SET kind = 'other' WHERE attendee_count < 2")
    op.create_check_constraint("ck_meetings_time_order", "meetings", "ends_at > starts_at")
    op.create_check_constraint(
        "ck_meetings_kind", "meetings", "kind IN ('meeting', 'focus', 'other')"
    )


def downgrade() -> None:
    op.drop_constraint("ck_meetings_kind", "meetings", type_="check")
    op.drop_constraint("ck_meetings_time_order", "meetings", type_="check")
    op.drop_column("meetings", "updated_at")
    op.drop_column("meetings", "agenda")
    op.drop_column("meetings", "kind")
