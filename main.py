from fastapi import FastAPI
from api.routes import auth as auth_router
# We will add other routers here as we build them (pages, me, vault, etc.)

app = FastAPI(
    title="Gibsey Bookclub MVP API",
    version="0.1.0",
    description="API for the Gibsey Bookclub MVP - Read, Ask, Earn, Share."
)

# Include routers
app.include_router(auth_router.router, prefix="/api/v1", tags=["Authentication"])

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