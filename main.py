from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
import pathlib
from api.routes import auth as auth_router
from api.routes import pages as pages_router
from api.routes import ask as ask_router
from api.routes import me as me_router
from api.routes import vault as vault_router
from api.routes import ledger as ledger_router
from api.routes import onboard as onboard_router
from core.auth import get_current_user
from typing import Dict, Any
# We will add other routers here as we build them (pages, me, vault, etc.)

PROJECT_ROOT = pathlib.Path(__file__).resolve().parent
STATIC_FILES_DIR = PROJECT_ROOT / "frontend" / "dist"

app = FastAPI(
    title="Gibsey Bookclub MVP API",
    version="0.1.0",
    description="API for the Gibsey Bookclub MVP - Read, Ask, Earn, Share."
)

# CORS Middleware
origins = [
    "http://localhost:5173", # Vite dev server
    "http://localhost:3000", # Common alternative for React dev servers
    "https://b376-2600-100d-a0ed-1bea-a059-db35-c971-3724.ngrok-free.app" # <--- Added your Ngrok URL
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
app.include_router(vault_router.router, prefix="/api/v1/vault", tags=["Vault"])
app.include_router(ledger_router.router, prefix="/api/v1", tags=["Ledger"])
app.include_router(onboard_router.router, prefix="/api/v1/onboard", tags=["Onboarding"])

@app.get("/health", tags=["Server Health"])
async def health_check():
    return {"status": "healthy"}

# Serve Static Files (React frontend) - Mount this last
if STATIC_FILES_DIR.exists() and (STATIC_FILES_DIR / "index.html").exists():
    app.mount("/", StaticFiles(directory=STATIC_FILES_DIR, html=True), name="static-frontend")
    print(f"Serving static files from: {STATIC_FILES_DIR}")
else:
    print(f"WARNING: Static files directory not found or index.html missing: {STATIC_FILES_DIR}")
    print("Frontend will not be served by FastAPI. Run `cd frontend && npm run build`")

# To run this app (from project root for production-like serving):
# .venv/bin/python -m uvicorn main:app --host 0.0.0.0 --port 8000 