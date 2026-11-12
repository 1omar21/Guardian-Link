from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.config import get_settings
from app.routers import auth, tasks, family, location, alerts, browsing

# Get settings
settings = get_settings()

# Create FastAPI app
app = FastAPI(
    title="GuardianLink API",
    description="Backend for GuardianLink - child safety, location tracking and gamified rewards",
    version="1.0.0",
    debug=settings.debug
)

# Configure CORS
# Exact origins go to allow_origins; entries with "*" (e.g. http://localhost:*)
# are converted to a regex, because CORSMiddleware doesn't expand wildcards.
import re

_origins = [o.strip() for o in settings.allowed_origins.split(",") if o.strip()]
_exact = [o for o in _origins if "*" not in o]
_patterns = [re.escape(o).replace(r"\*", r"[^/]*") for o in _origins if "*" in o]

app.add_middleware(
    CORSMiddleware,
    allow_origins=_exact,
    allow_origin_regex=("^(" + "|".join(_patterns) + ")$") if _patterns else None,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Include routers
app.include_router(auth.router, prefix="/api/auth", tags=["Authentication"])
app.include_router(location.router, prefix="/api/location", tags=["location"])
app.include_router(tasks.router, prefix="/api/tasks", tags=["Tasks"])
app.include_router(family.router, prefix="/api/family", tags=["Family Management"])
app.include_router(alerts.router, prefix="/api/alerts", tags=["Alerts (SOS, safe zones)"])
app.include_router(browsing.router, prefix="/api/browsing", tags=["Browsing history"])


@app.get("/")
async def root():
    """Root endpoint - API health check."""
    return {
        "message": "GuardianLink API",
        "version": "1.0.0",
        "status": "running",
        "docs": "/docs"
    }


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app.main:app",
        host=settings.api_host,
        port=settings.api_port,
        reload=settings.debug
    )
