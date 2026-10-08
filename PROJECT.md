# Spry: project specification

Spry turns a team's meetings into insights: how much time goes to meetings, how much is left for
deep work, and which upcoming meetings have no agenda. This file describes what is in the
repository and the contract between backend and frontend. Nothing here is aspirational: every
endpoint listed exists and is covered by a test.

## 1. Repository layout (monorepo)

```
backend/    FastAPI, SQLAlchemy 2 (async), Alembic          -> the only thing that touches the database
  app/api/routes/    HTTP only: parse, validate, call a service, shape the response
  app/services/      business logic; schedule.py is pure maths with no DB, HTTP or clock
  app/models/        SQLAlchemy tables
  app/schemas/       Pydantic request/response models (the API contract)
  migrations/        Alembic revisions; the schema changes only through these
  tests/             pytest against a real PostgreSQL, each test in a rolled-back transaction
frontend/   Next.js (static export), Tailwind, shadcn/ui     -> talks to the backend over HTTP only
  app/(app)/page.tsx      the dashboard at /: weekly numbers, week calendar, deep work, agenda readiness
  app/(app)/meetings/     every meeting in a table, with edit and delete
  components/             one component per card; ui/ holds the shadcn primitives
  lib/api.ts              the only place that calls the backend; zod schemas mirror section 3
  lib/queries.ts          React Query hooks; any change refreshes meetings, insights, slots and readiness
  lib/time.ts             all date maths, in the working timezone (Europe/Kyiv)
infra/      CloudFormation: ECS Fargate + ALB + RDS, S3 + CloudFront, GitHub OIDC role
scripts/    deploy / destroy helpers behind the Makefile
docker-compose.yml   db + backend + frontend; `docker compose up --build` is the one command
```

Rule: backend and frontend share no source. The HTTP API below is their only contract.

## 2. Data model

`meetings`

| column | type | notes |
|---|---|---|
| id | integer pk | |
| title | varchar(255) | |
| starts_at, ends_at | timestamptz | `ends_at > starts_at` is enforced by a CHECK constraint |
| attendee_count | integer | >= 1 |
| kind | varchar(10) | `meeting` (2+ attendees), `focus` (deep-work block), `other`; CHECK constrained |
| agenda | text, nullable | null or blank means "no agenda" |
| created_at, updated_at | timestamptz | |

Revisions: `0001` init, `0002` meetings table, `0003` kind / agenda / updated_at / constraints.

## 3. API contract

Base path `/api`. JSON. Datetimes are ISO 8601 with offset. Errors: `{"detail": ...}`.
`GET /health` is liveness; `GET /api/health/ready` also runs `SELECT 1`.

`Meeting` = `{id, title, starts_at, ends_at, attendee_count, kind, agenda, has_agenda}`

| Method | Path | Body / query | Result |
|---|---|---|---|
| GET | `/api/meetings` | `starts_after`, `starts_before`, `kind` (all optional) | `200 Meeting[]`, oldest first |
| POST | `/api/meetings` | `{title, starts_at, ends_at, attendee_count?, kind?, agenda?}` | `201 Meeting`. `kind` defaults to `meeting` if 2+ attendees, else `other` |
| GET | `/api/meetings/{id}` | | `200 Meeting`, `404` |
| PATCH | `/api/meetings/{id}` | any subset of the create fields; `agenda: null` clears it | `200 Meeting`, `404`, `422` if the merged times are inverted |
| DELETE | `/api/meetings/{id}` | | `204`, `404` |
| GET | `/api/insights/week` | `week_of` (any date in the week; default: this week) | `200 WeekInsights` |
| GET | `/api/agenda/readiness` | | `200 AgendaReadiness` (next 7 days) |
| GET | `/api/deep-work/slots` | | `200 SlotProposal` (this week and next) |
| POST | `/api/deep-work/reserve` | `{starts_at, ends_at, title?}` | `201 Meeting` of kind `focus`; `409` if it overlaps a meeting or focus block |

```
WeekInsights    {week_start, week_end, timezone,
                 meeting_minutes, meeting_count, deep_work_minutes}   each = {value, previous, change_pct|null}
AgendaReadiness {window_days, upcoming, without_agenda, without_agenda_pct, meetings: Meeting[]}
SlotProposal    {slots: [{starts_at, ends_at, minutes}], total_minutes}
```

Definitions (all in `backend/app/services/schedule.py`, all tested):

- Only `kind = meeting` counts as meeting time. A meeting belongs to the ISO week it starts in.
- Working week: Monday to Friday, 09:00 to 18:00, `Europe/Kyiv` (settings `WORK_TIMEZONE`, `WORK_START_HOUR`, `WORK_END_HOUR`).
- Deep work: contiguous free time of at least 60 minutes inside working hours.
- Proposed slots: free gaps of at least 120 minutes that start no earlier than now. Both meetings and focus blocks count as busy.
- `change_pct` compares with the previous week and is `null` when the previous value is 0.

## 4. Configuration

Environment variables only (`backend/app/config.py`, template in `.env.example`):
`DATABASE_URL`, `APP_ENV`, `LOG_LEVEL`, `CORS_ORIGINS`, `WORK_TIMEZONE`, `WORK_START_HOUR`,
`WORK_END_HOUR`, `DEEP_WORK_MIN_MINUTES`, `DEEP_WORK_BLOCK_MINUTES`.

## 5. Not built yet

Authentication and organisations (FR-1 to FR-4), real Google Calendar sync (FR-5, FR-6), email
(FR-21, FR-22), CSV export and audit log (FR-23, FR-25), per-member working hours (FR-8). Every
meeting today is entered by hand or created through the API.
