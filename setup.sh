#!/bin/bash

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to wait for a service to be healthy
wait_for_service() {
    local service=$1
    local max_attempts=$2
    local attempt=1
    
    print_status "Waiting for $service to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        if docker ps --filter "name=$service" --filter "health=healthy" | grep -q "$service"; then
            print_success "$service is healthy"
            return 0
        fi
        
        echo -n "."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    print_error "$service failed to become healthy"
    return 1
}

# Function to wait for a port to be available
wait_for_port() {
    local port=$1
    local max_attempts=$2
    local attempt=1
    
    print_status "Waiting for port $port to be available..."
    
    while [ $attempt -le $max_attempts ]; do
        if nc -z localhost $port 2>/dev/null; then
            print_success "Port $port is available"
            return 0
        fi
        
        echo -n "."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    print_error "Port $port is not available"
    return 1
}

echo "=========================================="
echo "  SENTINEL FRAUD DETECTION PLATFORM"
echo "  Automated Setup Script"
echo "=========================================="
echo ""

# Step 1: Check prerequisites
print_status "Checking prerequisites..."

if ! command_exists docker; then
    print_error "Docker is not installed. Please install Docker Desktop first."
    exit 1
fi

if ! command_exists docker-compose && ! docker compose version >/dev/null 2>&1; then
    print_error "Docker Compose is not installed or not available."
    exit 1
fi

if ! command_exists python3; then
    print_error "Python 3 is not installed."
    exit 1
fi

# Check Docker daemon is running
if ! docker info >/dev/null 2>&1; then
    print_error "Docker daemon is not running. Please start Docker Desktop."
    exit 1
fi

print_success "All prerequisites are met"

# Step 2: Check system resources
print_status "Checking system resources..."

# Check available disk space (need at least 20GB)
available_space=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
if [ "$available_space" -lt 20 ]; then
    print_warning "Low disk space detected. At least 20GB recommended."
fi

# Check available RAM (need at least 8GB)
if command_exists free; then
    total_ram=$(free -g | grep Mem | awk '{print $2}')
    if [ "$total_ram" -lt 8 ]; then
        print_warning "Low RAM detected. At least 8GB recommended."
    fi
fi

print_success "System resources checked"

# Step 3: Setup environment file
print_status "Setting up environment configuration..."

cd infrastructure

if [ ! -f .env ]; then
    if [ -f .env.example ]; then
        cp .env.example .env
        print_success "Created .env from .env.example"
    else
        print_error ".env.example not found. Creating default .env..."
        cat > .env << 'EOF'
# PostgreSQL Configuration
POSTGRES_USER=sentinel_user
POSTGRES_PASSWORD=sentinel_secure_pass
POSTGRES_DB=feast_registry

# MinIO Configuration
MINIO_ROOT_USER=minio_admin
MINIO_ROOT_PASSWORD=minio_secure_pass
MLFLOW_BUCKET_NAME=mlflow

# Airflow Configuration
AIRFLOW_UID=50000
AIRFLOW__CORE__EXECUTOR=LocalExecutor
AIRFLOW__CORE__SQL_ALCHEMY_CONN=postgresql+psycopg2://sentinel_user:sentinel_secure_pass@db:5432/airflow_db
AIRFLOW__CORE__FERNET_KEY=
AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION=True
AIRFLOW__CORE__LOAD_EXAMPLES=False
AIRFLOW__API__AUTH_BACKENDS=airflow.api.auth.backend.basic_auth,airflow.api.auth.backend.session
AIRFLOW__SCHEDULER__ENABLE_HEALTH_CHECK=True
_AIRFLOW_DB_MIGRATE=true
_AIRFLOW_WWW_USER_CREATE=true
_AIRFLOW_WWW_USER_USERNAME=admin
_AIRFLOW_WWW_USER_PASSWORD=admin
EOF
        print_success "Created default .env file"
    fi
else
    print_warning ".env already exists, skipping..."
fi

cd ..

# Step 4: Check if Python environment exists
print_status "Checking Python environment..."

if command_exists conda; then
    if conda env list | grep -q "^fdp "; then
        print_success "Conda environment 'fdp' already exists"
    else
        print_status "Creating conda environment 'fdp'..."
        conda create -n fdp python=3.10 -y
        print_success "Conda environment created"
    fi
    
    print_status "Installing Python dependencies..."
    eval "$(conda shell.bash hook)"
    conda activate fdp
    pip install boto3 python-dotenv pandas
    print_success "Python dependencies installed"
else
    print_warning "Conda not found. Skipping Python environment setup."
    print_warning "You'll need to install dependencies manually: pip install boto3 python-dotenv pandas"
fi

# Step 5: Stop any existing containers
print_status "Checking for existing containers..."

if docker ps -a | grep -q "sentinel"; then
    print_warning "Found existing Sentinel containers. Stopping them..."
    cd infrastructure
    docker compose down
    cd ..
    print_success "Stopped existing containers"
fi

# Step 6: Pull and build Docker images
print_status "Building Docker images (this may take 5-10 minutes)..."

cd infrastructure
docker compose build
print_success "Docker images built successfully"

# Step 7: Start infrastructure
print_status "Starting infrastructure services..."

docker compose up -d

print_success "All services started"

# Step 8: Wait for services to be healthy
print_status "Waiting for services to initialize (this may take 60-90 seconds)..."

# Wait for PostgreSQL
wait_for_service "sentinel_db" 30

# Wait for Redis
wait_for_port 6379 30

# Wait for MinIO
wait_for_port 9000 30

# Wait for MLflow
wait_for_port 5000 30

# Wait for Airflow (longer timeout)
sleep 30  # Give Airflow extra time to initialize
wait_for_port 8080 60

print_success "All services are healthy"

cd ..

# Step 9: Create MinIO bucket
print_status "Creating MinIO bucket..."

if [ -f create_bucket.py ]; then
    python create_bucket.py
    if [ $? -eq 0 ]; then
        print_success "MinIO bucket created"
    else
        print_error "Failed to create MinIO bucket"
        print_warning "You may need to create it manually: python create_bucket.py"
    fi
else
    print_error "create_bucket.py not found"
fi

# Step 10: Verify setup
print_status "Running system verification..."

if [ -f verify_setup.sh ]; then
    chmod +x verify_setup.sh
    ./verify_setup.sh
else
    print_warning "verify_setup.sh not found, skipping verification"
fi

# Step 11: Display summary
echo ""
echo "=========================================="
echo "  SETUP COMPLETE!"
echo "=========================================="
echo ""
print_success "Sentinel Fraud Detection Platform is ready!"
echo ""
echo "📊 Service URLs:"
echo "   • Airflow UI:    http://localhost:8080 (admin/admin)"
echo "   • MLflow UI:     http://localhost:5000"
echo "   • API Docs:      http://localhost:8000/docs"
echo "   • Dashboard:     http://localhost:8501"
echo "   • MinIO Console: http://localhost:9001 (minio_admin/minio_secure_pass)"
echo ""
echo "🚀 Next Steps:"
echo "   1. Open Airflow UI: http://localhost:8080"
echo "   2. Log in with: admin / admin"
echo "   3. Enable the DAG: sentinel_mlops_pipeline"
echo "   4. Click 'Trigger DAG' to start the ML pipeline"
echo "   5. Wait 5-10 minutes for pipeline completion"
echo "   6. Test the API: curl http://localhost:8000/predict/2987000"
echo ""
echo "📝 Logs:"
echo "   • View all logs:     docker compose logs -f"
echo "   • Airflow logs:      docker logs sentinel_scheduler -f"
echo "   • API logs:          docker logs sentinel_api -f"
echo ""
echo "🛑 To stop all services:"
echo "   cd infrastructure && docker compose down"
echo ""
echo "❓ Troubleshooting:"
echo "   • Run: ./verify_setup.sh"
echo "   • Check README.md for common issues"
echo ""
echo "=========================================="

# Optional: Open browser to Airflow
if command_exists xdg-open; then
    read -p "Do you want to open Airflow UI in your browser? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        xdg-open http://localhost:8080
    fi
elif command_exists open; then
    read -p "Do you want to open Airflow UI in your browser? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        open http://localhost:8080
    fi
fi

exit 0