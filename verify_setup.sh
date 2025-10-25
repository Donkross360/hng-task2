#!/bin/bash

# Verify Blue/Green setup
# Usage: ./verify_setup.sh

set -e

echo "🔍 Verifying Blue/Green Setup"
echo "=============================="

# Check required files
echo ""
echo "Checking files..."
if [ ! -f "docker-compose.yaml" ]; then
    echo "❌ docker-compose.yaml not found"
    exit 1
fi

if [ ! -f "nginx.conf.template" ]; then
    echo "❌ nginx.conf.template not found"
    exit 1
fi

if [ ! -f ".env" ]; then
    echo "⚠️  .env file not found (will need to be created)"
else
    echo "✅ .env file exists"
fi

# Check .env variables
echo ""
echo "Checking environment variables..."
source .env 2>/dev/null || true

required_vars=("BLUE_IMAGE" "GREEN_IMAGE" "ACTIVE_POOL" "RELEASE_ID_BLUE" "RELEASE_ID_GREEN")
missing_vars=()

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        missing_vars+=("$var")
    else
        echo "✅ $var = ${!var}"
    fi
done

if [ ${#missing_vars[@]} -ne 0 ]; then
    echo ""
    echo "⚠️  Missing environment variables:"
    for var in "${missing_vars[@]}"; do
        echo "   - $var"
    done
    echo ""
    echo "Create a .env file with these variables"
fi

# Check docker-compose
echo ""
echo "Checking Docker Compose configuration..."
if command -v docker-compose &> /dev/null; then
    echo "✅ docker-compose is installed"
    
    # Validate docker-compose file
    if docker-compose config > /dev/null 2>&1; then
        echo "✅ docker-compose.yaml is valid"
    else
        echo "❌ docker-compose.yaml has errors"
        docker-compose config
        exit 1
    fi
else
    echo "❌ docker-compose is not installed"
    exit 1
fi

# Check if containers are running
echo ""
echo "Checking running containers..."
if docker ps --format '{{.Names}}' | grep -q "nginx-lb\|blue-app\|green-app"; then
    echo "✅ Containers are running:"
    docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E "nginx-lb|blue-app|green-app"
else
    echo "⚠️  No containers are running yet"
    echo "   Run: docker-compose up -d"
fi

# Summary
echo ""
echo "=============================="
echo "✅ Setup verification complete"
echo "=============================="
