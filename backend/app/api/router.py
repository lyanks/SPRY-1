from fastapi import APIRouter

from app.api.routes import health, insights, meetings

api_router = APIRouter(prefix="/api")
api_router.include_router(health.router)
api_router.include_router(meetings.router)
api_router.include_router(insights.router)
