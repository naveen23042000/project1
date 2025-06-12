#!/bin/bash
# Deploy script for Docker containers
set -e

echo "🚀 Starting deployment process..."

# Variables
CONTAINER_NAME="project1-container"
IMAGE_NAME="project1"
DOCKER_HUB_USERNAME="naveenkumar492"
PORT="${DEPLOY_PORT:-8080}"  # Changed default port to 8080 to avoid conflicts

# Get current git branch - handle Jenkins environment
if [ -n "$BRANCH_NAME" ]; then
    # Jenkins environment variable
    BRANCH="$BRANCH_NAME"
elif [ -n "$GIT_BRANCH" ]; then
    # Alternative Jenkins variable (remove origin/ prefix if present)
    BRANCH="${GIT_BRANCH#origin/}"
else
    # Fallback to git command
    BRANCH=$(git rev-parse --abbrev-ref HEAD)
fi

echo "Current branch: $BRANCH"

# Function to check if port is available
check_port() {
    local port=$1
    # Check using multiple methods for better reliability
    if command -v lsof >/dev/null 2>&1; then
        if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
            return 1
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tuln | grep -q ":$port "; then
            return 1
        fi
    elif command -v ss >/dev/null 2>&1; then
        if ss -tuln | grep -q ":$port "; then
            return 1
        fi
    fi
    
    # Also check if any Docker container is using this port
    if docker ps --format "{{.Ports}}" | grep -q ":$port->"; then
        return 1
    fi
    
    return 0
}

# Function to find available port
find_available_port() {
    local start_port=$1
    local max_attempts=20
    local current_port=$start_port
    
    for ((i=0; i<max_attempts; i++)); do
        if check_port $current_port; then
            echo $current_port
            return 0
        fi
        current_port=$((current_port + 1))
    done
    
    return 1
}

# Function to wait for container to be healthy
wait_for_container() {
    local container_name=$1
    local max_attempts=30
    local attempt=1
    
    echo "⏳ Waiting for container to be ready..."
    while [ $attempt -le $max_attempts ]; do
        if docker ps --filter "name=$container_name" --filter "status=running" | grep -q $container_name; then
            echo "✅ Container is running (attempt $attempt/$max_attempts)"
            return 0
        fi
        echo "🔄 Waiting... (attempt $attempt/$max_attempts)"
        sleep 2
        attempt=$((attempt + 1))
    done
    
    echo "❌ Container failed to start within expected time"
    return 1
}

# Stop and remove existing container - improved cleanup
echo "🛑 Cleaning up existing deployment..."
# Stop container if running
if docker ps -q --filter "name=$CONTAINER_NAME" | grep -q .; then
    echo "Stopping existing container..."
    docker stop $CONTAINER_NAME 2>/dev/null || true
    sleep 2  # Give it time to stop
fi

# Remove container if exists
if docker ps -aq --filter "name=$CONTAINER_NAME" | grep -q .; then
    echo "Removing existing container..."
    docker rm $CONTAINER_NAME 2>/dev/null || true
fi

# Remove any dangling containers with the same name pattern
docker container prune -f >/dev/null 2>&1 || true

# Check and handle port availability
echo "🔍 Checking port availability..."
if ! check_port $PORT; then
    echo "⚠️ Port $PORT is already in use"
    echo "🔧 Port $PORT is not available, trying to find an alternative..."
    AVAILABLE_PORT=$(find_available_port $PORT)
    if [ $? -eq 0 ] && [ ! -z "$AVAILABLE_PORT" ]; then
        PORT=$AVAILABLE_PORT
        echo "✅ Using alternative port: $PORT"
    else
        echo "❌ Could not find available port. Trying to force cleanup..."
        
        # Try to force stop any container using the port
        CONFLICTING_CONTAINER=$(docker ps --filter "publish=$PORT" --quiet)
        if [ ! -z "$CONFLICTING_CONTAINER" ]; then
            echo "🛑 Force stopping container using port $PORT..."
            docker stop $CONFLICTING_CONTAINER || true
            docker rm $CONFLICTING_CONTAINER || true
            sleep 3
            
            # Check again
            if check_port $PORT; then
                echo "✅ Port $PORT is now available"
            else
                echo "❌ Port $PORT is still not available. Please manually check what's using this port."
                exit 1
            fi
        else
            echo "❌ Port $PORT is not available and no Docker container conflict detected."
            echo "Please check what system service is using port $PORT or set DEPLOY_PORT environment variable."
            exit 1
        fi
    fi
else
    echo "✅ Port $PORT is available"
fi

# Deploy based on branch
echo "🚀 Starting new deployment..."
if [ "$BRANCH" = "dev" ]; then
    echo "Deploying dev version..."
    IMAGE_TO_DEPLOY="$DOCKER_HUB_USERNAME/dev:dev"
    
elif [ "$BRANCH" = "master" ] || [ "$BRANCH" = "main" ]; then
    echo "Deploying production version..."
    IMAGE_TO_DEPLOY="$DOCKER_HUB_USERNAME/prod:prod"
    
else
    echo "Deploying feature branch version..."
    # For feature branches, use the sanitized branch name
    SAFE_BRANCH=$(echo "$BRANCH" | sed 's/[^a-zA-Z0-9._-]/-/g')
    IMAGE_TO_DEPLOY="$DOCKER_HUB_USERNAME/dev:$SAFE_BRANCH"
    
    # Check if the feature branch image exists, fallback to latest if not
    if ! docker image inspect $IMAGE_TO_DEPLOY >/dev/null 2>&1; then
        echo "Feature branch image not found, using local latest image..."
        IMAGE_TO_DEPLOY="$IMAGE_NAME:latest"
    fi
fi

echo "📦 Deploying image: $IMAGE_TO_DEPLOY"

# Try to pull the image first (if it's from Docker Hub)
if [[ $IMAGE_TO_DEPLOY == *"$DOCKER_HUB_USERNAME"* ]]; then
    echo "📥 Pulling latest image..."
    docker pull $IMAGE_TO_DEPLOY || echo "⚠️  Could not pull image, using local version"
fi

# Deploy the container
echo "🚀 Starting container..."
CONTAINER_ID=$(docker run -d \
    --name $CONTAINER_NAME \
    -p $PORT:80 \
    --restart unless-stopped \
    $IMAGE_TO_DEPLOY)

if [ $? -eq 0 ]; then
    echo "✅ Container started with ID: ${CONTAINER_ID:0:12}"
else
    echo "❌ Failed to start container"
    exit 1
fi

# Wait for container to be ready
if wait_for_container $CONTAINER_NAME; then
    echo "✅ Container deployed successfully!"
    
    # Display deployment info
    echo ""
    echo "📋 Deployment Summary:"
    echo "  🌟 Branch: $BRANCH"
    echo "  📦 Image: $IMAGE_TO_DEPLOY"
    echo "  🐳 Container: $CONTAINER_NAME"
    echo "  🌐 URL: http://localhost:$PORT"
    echo "  🔄 Restart Policy: unless-stopped"
    
    # Show container status
    echo ""
    echo "📊 Container Status:"
    docker ps --filter "name=$CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    # Test if the application is responding
    echo ""
    echo "🧪 Testing application response..."
    if command -v curl >/dev/null 2>&1; then
        sleep 5  # Give more time for the app to start
        HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT 2>/dev/null || echo "000")
        if [ "$HTTP_STATUS" = "200" ]; then
            echo "✅ Application is responding successfully!"
        elif [ "$HTTP_STATUS" = "000" ]; then
            echo "⚠️  Could not connect to application (connection refused)"
        else
            echo "⚠️  Application returned HTTP status: $HTTP_STATUS"
        fi
    else
        echo "ℹ️  curl not available, skipping response test"
    fi
    
else
    echo "❌ Deployment failed!"
    echo ""
    echo "🔍 Container logs:"
    docker logs $CONTAINER_NAME 2>/dev/null || echo "No logs available"
    echo ""
    echo "🔍 Container inspect:"
    docker inspect $CONTAINER_NAME --format='{{.State.Status}}: {{.State.Error}}' 2>/dev/null || echo "Container not found"
    exit 1
fi

echo ""
echo "🎉 Deployment completed successfully!"
echo "🌐 Access your application at: http://localhost:$PORT"