#!/bin/bash

echo "======================================"
echo "SENTINEL FRAUD DETECTION - SYSTEM CHECK"
echo "======================================"
echo ""

echo "1. Checking for localhost references..."
echo "   (Excluding create_bucket.py and test files)"
grep -rn "localhost" \
  --include="*.py" \
  --include="*.yaml" \
  --exclude="create_bucket.py" \
  --exclude="test_*.py" \
  . 2>/dev/null || echo "   ✅ No localhost found"

echo ""
echo "2. Checking Docker containers..."
docker ps --format "table {{.Names}}\t{{.Status}}" | grep sentinel

echo ""
echo "3. Testing connections from Airflow..."
echo "   PostgreSQL:"
docker exec sentinel_scheduler python -c "import psycopg2; psycopg2.connect('host=sentinel_db port=5432 user=sentinel_user password=sentinel_secure_pass dbname=feast_registry'); print('   ✅ OK')" 2>&1 | grep -E "(✅|Error)"

echo "   Redis:"
docker exec sentinel_scheduler python -c "import redis; redis.Redis(host='sentinel_redis', port=6379).ping(); print('   ✅ OK')" 2>&1 | grep -E "(✅|Error)"

echo "   MLflow:"
docker exec sentinel_scheduler curl -s http://sentinel_mlflow:5000/health > /dev/null && echo "   ✅ OK" || echo "   ❌ Failed"

echo ""
echo "4. Checking feature_store.yaml..."
docker exec sentinel_scheduler grep -E "(sentinel_db|sentinel_redis)" /app/feature_store/feature_store.yaml && echo "   ✅ Uses Docker service names" || echo "   ❌ Still using localhost"

echo ""
echo "======================================"
echo "SYSTEM CHECK COMPLETE"
echo "======================================"
