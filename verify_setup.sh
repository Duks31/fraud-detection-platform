#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

print_check() {
    echo -e "${BLUE}[CHECK]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
    WARNINGS=$((WARNINGS + 1))
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
    ERRORS=$((ERRORS + 1))
}

echo "=========================================="
echo "  SENTINEL SYSTEM VERIFICATION"
echo "=========================================="
echo ""

# 1. Check Docker is running
print_check "Checking Docker daemon..."
if docker info >/dev/null 2>&1; then
    print_success "Docker is running"
else
    print_error "Docker daemon is not running"
    exit 1
fi

# 2. Check containers
print_check "Checking containers..."

expected_containers=(
    "sentinel_db"
    "sentinel_minio"
    "sentinel_mlflow"
    "sentinel_redis"
    "sentinel_airflow"
    "sentinel_scheduler"
    "sentinel_api"
    "sentinel_dashboard"
)

for container in "${expected_containers[@]}"; do
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        status=$(docker inspect --format='{{.State.Status}}' "$container")
        if [ "$status" = "running" ]; then
            print_success "Container $container is running"
        else
            print_error "Container $container exists but is not running (status: $status)"
        fi
    else
        print_error "Container $container not found"
    fi
done

# 3. Check container health (for containers with health checks)
print_check "Checking container health..."

if docker ps --filter "name=sentinel_db" --filter "health=healthy" | grep -q "sentinel_db"; then
    print_success "PostgreSQL is healthy"
else
    print_warning "PostgreSQL health check not passing (may still be starting)"
fi

# 4. Check ports
print_check "Checking port availability..."

ports=(
    "5432:PostgreSQL"
    "6379:Redis"
    "9000:MinIO"
    "9001:MinIO Console"
    "5000:MLflow"
    "8080:Airflow"
    "8000:API"
    "8501:Dashboard"
)

for port_info in "${ports[@]}"; do
    port="${port_info%%:*}"
    service="${port_info##*:}"
    
    if nc -z localhost "$port" 2>/dev/null || (echo > /dev/tcp/localhost/$port) 2>/dev/null; then
        print_success "Port $port ($service) is accessible"
    else
        print_error "Port $port ($service) is not accessible"
    fi
done

# 5. Check PostgreSQL connection
print_check "Checking PostgreSQL connection..."

if docker exec sentinel_db pg_isready -U sentinel_user >/dev/null 2>&1; then
    print_success "PostgreSQL is accepting connections"
    
    # Check databases exist
    for db in feast_registry airflow_db sentinel_db; do
        if docker exec sentinel_db psql -U sentinel_user -lqt | cut -d \| -f 1 | grep -qw "$db"; then
            print_success "Database '$db' exists"
        else
            print_error "Database '$db' not found"
        fi
    done
else
    print_error "Cannot connect to PostgreSQL"
fi

# 6. Check Redis
print_check "Checking Redis..."

if docker exec sentinel_redis redis-cli ping >/dev/null 2>&1; then
    print_success "Redis is responding to pings"
    
    # Check feature count
    feature_count=$(docker exec sentinel_redis redis-cli DBSIZE | grep -o '[0-9]*')
    if [ "$feature_count" -gt 0 ]; then
        print_success "Redis contains $feature_count keys (features materialized)"
    else
        print_warning "Redis is empty (features not materialized yet)"
    fi
else
    print_error "Cannot connect to Redis"
fi

# 7. Check MinIO
print_check "Checking MinIO..."

if curl -s http://localhost:9000/minio/health/live >/dev/null 2>&1; then
    print_success "MinIO is healthy"
    
    # Check bucket exists
    if docker exec -it sentinel_scheduler python -c "
import boto3
try:
    s3 = boto3.client('s3', endpoint_url='http://s3:9000', aws_access_key_id='minio_admin', aws_secret_access_key='minio_secure_pass')
    buckets = [b['Name'] for b in s3.list_buckets()['Buckets']]
    print('mlflow' in buckets)
except:
    print('False')
" 2>/dev/null | grep -q "True"; then
        print_success "MinIO bucket 'mlflow' exists"
    else
        print_error "MinIO bucket 'mlflow' not found - run: python create_bucket.py"
    fi
else
    print_error "MinIO is not responding"
fi

# 8. Check MLflow
print_check "Checking MLflow..."

if curl -s http://localhost:5000/health >/dev/null 2>&1; then
    print_success "MLflow is responding"
    
    # Check if experiments exist
    if docker exec -it sentinel_scheduler python -c "
import mlflow
mlflow.set_tracking_uri('http://sentinel_mlflow:5000')
try:
    exp = mlflow.get_experiment_by_name('Fraud detection')
    print(exp is not None)
except:
    print('False')
" 2>/dev/null | grep -q "True"; then
        print_success "MLflow experiment 'Fraud detection' exists"
    else
        print_warning "MLflow experiment 'Fraud detection' not found (will be created on first run)"
    fi
else
    print_error "MLflow is not responding"
fi

# 9. Check Airflow
print_check "Checking Airflow..."

if curl -s http://localhost:8080/health >/dev/null 2>&1; then
    print_success "Airflow webserver is responding"
else
    print_error "Airflow webserver is not responding"
fi

# Check scheduler
if docker logs sentinel_scheduler 2>&1 | tail -20 | grep -q "Scheduler started"; then
    print_success "Airflow scheduler is running"
else
    print_warning "Airflow scheduler may still be initializing"
fi

# Check DAG exists
if docker exec -it sentinel_scheduler bash -c "airflow dags list 2>/dev/null" | grep -q "sentinel_mlops_pipeline"; then
    print_success "DAG 'sentinel_mlops_pipeline' is registered"
else
    print_error "DAG 'sentinel_mlops_pipeline' not found"
fi

# 10. Check Feast
print_check "Checking Feast configuration..."

if docker exec -it sentinel_scheduler bash -c "cd /app/feature_store && feast feature-views list 2>/dev/null" | grep -q "transaction_stats"; then
    print_success "Feast feature view 'transaction_stats' is registered"
else
    print_warning "Feast feature views not applied yet (run DAG task 1)"
fi

# 11. Check API
print_check "Checking FastAPI..."

if curl -s http://localhost:8000/health >/dev/null 2>&1; then
    health_status=$(curl -s http://localhost:8000/health | grep -o '"status":"[^"]*' | cut -d'"' -f4)
    
    if [ "$health_status" = "healthy" ]; then
        print_success "API is healthy"
        
        # Check if model is loaded
        if curl -s http://localhost:8000/health | grep -q '"model_loaded":true'; then
            print_success "Model is loaded in API"
        else
            print_warning "Model not loaded yet (run DAG to train model)"
        fi
        
        # Check if feature store is loaded
        if curl -s http://localhost:8000/health | grep -q '"feature_store_loaded":true'; then
            print_success "Feature store is loaded in API"
        else
            print_warning "Feature store not loaded in API"
        fi
    else
        print_error "API is unhealthy"
    fi
else
    print_error "API is not responding"
fi

# 12. Check Dashboard
print_check "Checking Streamlit dashboard..."

if curl -s http://localhost:8501 >/dev/null 2>&1; then
    print_success "Dashboard is responding"
else
    print_warning "Dashboard is not responding"
fi

# 13. Check disk space
print_check "Checking disk space..."

available_space=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
if [ "$available_space" -lt 10 ]; then
    print_warning "Low disk space: ${available_space}GB available"
else
    print_success "Disk space OK: ${available_space}GB available"
fi

# 14. Check Docker volumes
print_check "Checking Docker volumes..."

expected_volumes=(
    "infrastructure_postgres_data"
    "infrastructure_minio_data"
    "infrastructure_redis_data"
)

for volume in "${expected_volumes[@]}"; do
    if docker volume ls | grep -q "$volume"; then
        print_success "Volume $volume exists"
    else
        print_error "Volume $volume not found"
    fi
done

# Summary
echo ""
echo "=========================================="
echo "  VERIFICATION SUMMARY"
echo "=========================================="

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    print_success "All checks passed! System is fully operational."
    echo ""
    echo "🚀 Ready to use:"
    echo "   • Airflow UI:  http://localhost:8080"
    echo "   • MLflow UI:   http://localhost:5000"
    echo "   • API Docs:    http://localhost:8000/docs"
    echo "   • Dashboard:   http://localhost:8501"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}System is operational with $WARNINGS warning(s)${NC}"
    echo ""
    echo "✓ Core services are running"
    echo "⚠ Some features may not be ready yet"
    echo ""
    echo "Next steps:"
    echo "  1. Trigger the Airflow DAG to complete setup"
    echo "  2. Wait for pipeline to finish (~5-10 minutes)"
    echo "  3. Run verification again: ./verify_setup.sh"
    exit 0
else
    echo -e "${RED}System check failed with $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    echo ""
    echo "Common fixes:"
    echo "  • Check Docker is running: docker info"
    echo "  • Restart services: cd infrastructure && docker compose restart"
    echo "  • View logs: docker compose logs -f"
    echo "  • Re-run setup: ./setup.sh"
    echo ""
    echo "See README.md Troubleshooting section for more help"
    exit 1
fi