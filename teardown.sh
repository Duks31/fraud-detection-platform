#!/bin/bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo "=========================================="
echo "  SENTINEL PLATFORM TEARDOWN"
echo "=========================================="
echo ""

print_warning "This will:"
echo "  • Stop all running containers"
echo "  • Remove all containers"
echo "  • Remove Docker networks"
echo "  • Optionally remove volumes (data will be lost)"
echo ""

read -p "Are you sure you want to continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

cd infrastructure

# Stop and remove containers
echo "Stopping containers..."
docker compose down

print_success "Containers stopped and removed"

# Ask about volumes
echo ""
read -p "Do you want to remove volumes? This will delete all data! (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker compose down -v
    print_success "Volumes removed"
else
    echo "Volumes preserved"
fi

# Ask about images
echo ""
read -p "Do you want to remove Docker images? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker compose down --rmi all
    print_success "Images removed"
else
    echo "Images preserved"
fi

cd ..

echo ""
print_success "Teardown complete!"
echo ""
echo "To start again, run: ./setup.sh"
echo ""