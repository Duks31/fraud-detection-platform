#!/bin/bash
echo "=== Checking for localhost references ==="
echo ""
echo "Python files:"
find . -name "*.py" -exec grep -l "localhost" {} \;
echo ""
echo "YAML files:"
find . -name "*.yaml" -exec grep -l "localhost" {} \;
echo ""
echo "Env files:"
find . -name ".env" -exec grep -l "localhost" {} \;
