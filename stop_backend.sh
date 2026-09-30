#!/bin/bash

# GuardianLink - Stop Backend Script

echo "🛑 Stopping GuardianLink Backend..."

# Kill the backend process
if pgrep -f "uvicorn app.main:app" > /dev/null; then
    pkill -f "uvicorn app.main:app"
    echo "✅ Backend stopped successfully!"
    
    # Remove PID file if it exists
    if [ -f "backend/backend.pid" ]; then
        rm backend/backend.pid
    fi
else
    echo "⚠️  Backend is not running."
fi
