from fastapi import FastAPI, Depends
from api.routes import auth as auth_router
from api.routes import pages as pages_router
from core.auth import get_current_user
from typing import Dict, Any
# We will add other routers here as we build them (pages, me, vault, etc.)

app = FastAPI(
    title="Gibsey Bookclub MVP API",
    version="0.1.0",
    description="API for the Gibsey Bookclub MVP - Read, Ask, Earn, Share."
)

# Include routers
app.include_router(auth_router.router, prefix="/api/v1", tags=["Authentication"])
app.include_router(pages_router.router, prefix="/api/v1", tags=["Pages"])

@app.get("/api/v1/users/me", tags=["Users"], response_model=Dict[str, Any])
async def read_users_me(current_user: Dict[str, Any] = Depends(get_current_user)):
    """Fetch the currently authenticated user's details."""
    return current_user

@app.get("/health", tags=["Server Health"])
async def health_check():
    return {"status": "healthy"}

# In a real app, you might have a function to close DB connection on shutdown:
# @app.on_event("shutdown")
# def shutdown_event():
#     from core.db import con
#     con.close()
#     print("Database connection closed.")

# To run this app (from project root):
# uvicorn main:app --reload --host 0.0.0.0 --port 8000 