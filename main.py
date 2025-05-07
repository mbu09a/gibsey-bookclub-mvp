from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
from api.routes import auth as auth_router
from api.routes import pages as pages_router
from api.routes import ask as ask_router
from api.routes import me as me_router
from core.auth import get_current_user
from typing import Dict, Any
# We will add other routers here as we build them (pages, me, vault, etc.)

app = FastAPI(
    title="Gibsey Bookclub MVP API",
    version="0.1.0",
    description="API for the Gibsey Bookclub MVP - Read, Ask, Earn, Share."
)

# CORS Middleware
origins = [
    "http://localhost:5173", # Vite dev server
    "http://localhost:3000", # Common alternative for React dev servers
    # Add any other origins if needed, e.g., your production frontend URL
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True, # Allows cookies to be sent/received
    allow_methods=["*"],    # Allows all methods (GET, POST, etc.)
    allow_headers=["*"],    # Allows all headers
)

# Include routers
app.include_router(auth_router.router, prefix="/api/v1", tags=["Authentication"])
app.include_router(pages_router.router, prefix="/api/v1", tags=["Pages"])
app.include_router(ask_router.router, prefix="/api/v1", tags=["Ask the Guide"])
app.include_router(me_router.router, prefix="/api/v1/users", tags=["Users"])

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