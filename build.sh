#!/bin/bash

# Build script for Docker images
set -e

echo "🚀 Starting Docker build process..."

# Variables
IMAGE_NAME="project1"
DEV_TAG="dev"
PROD_TAG="prod"
DOCKER_HUB_USERNAME="naveenkumar492"

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

# Build Docker image based on branch
if [ "$BRANCH" = "dev" ]; then
    echo "Building image for dev branch..."
    docker build -t $IMAGE_NAME:$DEV_TAG .
    docker tag $IMAGE_NAME:$DEV_TAG $DOCKER_HUB_USERNAME/dev:$DEV_TAG
    docker tag $IMAGE_NAME:$DEV_TAG $DOCKER_HUB_USERNAME/dev:latest
    echo "✅ Dev image built and tagged successfully!"
    echo "Tags created:"
    echo "  - $IMAGE_NAME:$DEV_TAG"
    echo "  - $DOCKER_HUB_USERNAME/dev:$DEV_TAG"
    echo "  - $DOCKER_HUB_USERNAME/dev:latest"
    
elif [ "$BRANCH" = "master" ] || [ "$BRANCH" = "main" ]; then
    echo "Building image for production branch..."
    docker build -t $IMAGE_NAME:$PROD_TAG .
    docker tag $IMAGE_NAME:$PROD_TAG $DOCKER_HUB_USERNAME/prod:$PROD_TAG
    docker tag $IMAGE_NAME:$PROD_TAG $DOCKER_HUB_USERNAME/prod:latest
    echo "✅ Production image built and tagged successfully!"
    echo "Tags created:"
    echo "  - $IMAGE_NAME:$PROD_TAG"
    echo "  - $DOCKER_HUB_USERNAME/prod:$PROD_TAG"
    echo "  - $DOCKER_HUB_USERNAME/prod:latest"
    
else
    echo "Building image for feature branch: $BRANCH"
    docker build -t $IMAGE_NAME:latest .
    # For feature branches, tag with branch name
    SAFE_BRANCH=$(echo "$BRANCH" | sed 's/[^a-zA-Z0-9._-]/-/g')
    docker tag $IMAGE_NAME:latest $DOCKER_HUB_USERNAME/dev:$SAFE_BRANCH
    echo "✅ Feature image built and tagged successfully!"
    echo "Tags created:"
    echo "  - $IMAGE_NAME:latest"
    echo "  - $DOCKER_HUB_USERNAME/dev:$SAFE_BRANCH"
fi

echo "Build process completed!"

# List all images for verification
echo "📋 Available Docker images:"
docker images | grep -E "(^REPOSITORY|$IMAGE_NAME|$DOCKER_HUB_USERNAME)"