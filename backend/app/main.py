from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.config import get_settings
from app.routers import auth, tasks, family, location, geofence

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
origins = settings.allowed_origins.split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Include routers
app.include_router(auth.router, prefix="/api/auth", tags=["Authentication"])
app.include_router(location.router, prefix="/api/location", tags=["location"])
app.include_router(tasks.router, prefix="/api/tasks", tags=["Tasks"])
app.include_router(family.router, prefix="/api/family", tags=["Family Management"])
app.include_router(geofence.router, prefix="/api/geofence", tags=["Geofence"])


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
