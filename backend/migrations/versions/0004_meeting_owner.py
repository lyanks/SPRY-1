"""meetings: owner_id, so every calendar belongs to one person

Revision ID: 0004
Revises: 0003
Create Date: 2026-10-17

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0004"
down_revision: str | None = "0003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Rows from before sign-in belong to nobody who can sign in; 'unclaimed'
    # keeps them in the table without showing them to anyone.
    op.add_column(
        "meetings",
        sa.Column("owner_id", sa.String(64), server_default="unclaimed", nullable=False),
    )
    op.alter_column("meetings", "owner_id", server_default=None)
    op.create_index("ix_meetings_owner_id", "meetings", ["owner_id"])


def downgrade() -> None:
    op.drop_index("ix_meetings_owner_id", table_name="meetings")
    op.drop_column("meetings", "owner_id")
