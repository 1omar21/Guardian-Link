#!/bin/bash

# GuardianLink - Auto Start Script
# This script starts the backend server automatically

echo "🚀 Starting GuardianLink Backend..."

# Navigate to backend directory
cd "$(dirname "$0")/backend"

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    echo "❌ Virtual environment not found. Please run setup.sh first."
    exit 1
fi

# Activate virtual environment
source venv/bin/activate

# Check if backend is already running
if pgrep -f "uvicorn app.main:app" > /dev/null; then
    echo "⚠️  Backend is already running!"
    echo "To restart, first run: pkill -f 'uvicorn app.main:app'"
    exit 0
fi

# Start backend server in background
echo "📡 Starting backend on http://192.168.100.41:8000"
nohup uvicorn app.main:app --reload --host 0.0.0.0 --port 8000 > backend.log 2>&1 &

# Get the process ID
BACKEND_PID=$!
echo $BACKEND_PID > backend.pid

# Wait a moment for server to start
sleep 3

# Check if server started successfully
if pgrep -f "uvicorn app.main:app" > /dev/null; then
    echo "✅ Backend started successfully!"
    echo "📝 Process ID: $BACKEND_PID"
    echo "📄 Logs: backend/backend.log"
    echo ""
    echo "To stop the backend, run:"
    echo "  pkill -f 'uvicorn app.main:app'"
    echo ""
    echo "To view logs:"
    echo "  tail -f backend/backend.log"
else
    echo "❌ Failed to start backend. Check backend/backend.log for errors."
    exit 1
fi
