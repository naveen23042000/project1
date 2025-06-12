#!/bin/bash
# Deploy script for Docker containers
set -e

echo "🚀 Starting deployment process..."

# Variables
CONTAINER_NAME="project1-container"
IMAGE_NAME="project1"
DOCKER_HUB_USERNAME="naveenkumar492"
PORT="${DEPLOY_PORT:-80}"  # Allow port override via environment variable

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
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo "⚠️  Port $port is already in use"
        return 1
    fi
    return 0
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

# Stop and remove existing container
echo "🛑 Cleaning up existing deployment..."
if docker ps -q --filter "name=$CONTAINER_NAME" | grep -q .; then
    echo "Stopping existing container..."
    docker stop $CONTAINER_NAME 2>/dev/null || true
fi

if docker ps -aq --filter "name=$CONTAINER_NAME" | grep -q .; then
    echo "Removing existing container..."
    docker rm $CONTAINER_NAME 2>/dev/null || true
fi

# Check if port is available
if ! check_port $PORT; then
    echo "❌ Port $PORT is not available. Please stop the service using this port or change DEPLOY_PORT."
    exit 1
fi

# Deploy based on branch
echo "🚀 Starting new deployment..."
if [ "$BRANCH" = "dev" ]; then
    echo "Deploying dev version..."
    IMAGE_TO_DEPLOY="$DOCKER_HUB_USERNAME/dev:dev"
    docker run -d \
        --name $CONTAINER_NAME \
        -p $PORT:80 \
        --restart unless-stopped \
        $IMAGE_TO_DEPLOY
    echo "📦 Deployed image: $IMAGE_TO_DEPLOY"
    
elif [ "$BRANCH" = "master" ] || [ "$BRANCH" = "main" ]; then
    echo "Deploying production version..."
    IMAGE_TO_DEPLOY="$DOCKER_HUB_USERNAME/prod:prod"
    docker run -d \
        --name $CONTAINER_NAME \
        -p $PORT:80 \
        --restart unless-stopped \
        $IMAGE_TO_DEPLOY
    echo "📦 Deployed image: $IMAGE_TO_DEPLOY"
    
else
    echo "Deploying feature branch version..."
    # For feature branches, use the sanitized branch name
    SAFE_BRANCH=$(echo "$BRANCH" | sed 's/[^a-zA-Z0-9._-]/-/g')
    IMAGE_TO_DEPLOY="$DOCKER_HUB_USERNAME/dev:$SAFE_BRANCH"
    
    # Check if the feature branch image exists, fallback to latest if not
    if docker image inspect $IMAGE_TO_DEPLOY >/dev/null 2>&1; then
        echo "Using feature branch image: $IMAGE_TO_DEPLOY"
    else
        echo "Feature branch image not found, using local latest image..."
        IMAGE_TO_DEPLOY="$IMAGE_NAME:latest"
    fi
    
    docker run -d \
        --name $CONTAINER_NAME \
        -p $PORT:80 \
        --restart unless-stopped \
        $IMAGE_TO_DEPLOY
    echo "📦 Deployed image: $IMAGE_TO_DEPLOY"
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
        sleep 3
        if curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT | grep -q "200"; then
            echo "✅ Application is responding successfully!"
        else
            echo "⚠️  Application may not be fully ready yet (this is normal for React apps)"
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