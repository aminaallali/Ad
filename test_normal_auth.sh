#!/bin/bash

# Replace these values with your actual GitLab instance details
GITLAB_URL="http://gitlab.local"
TOKEN="YOUR_PERSONAL_ACCESS_TOKEN_HERE"

echo "=== Testing Normal Authentication (Before Revocation) ==="

# Test 1: Verify token works with regular API authentication
echo "Testing regular API authentication..."
curl -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     "$GITLAB_URL/api/v4/user" \
     -w "\nHTTP Status: %{http_code}\n" \
     -s

echo ""
echo "=== Token should work normally at this point ==="
echo ""