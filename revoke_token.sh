#!/bin/bash

# Replace these values with your actual GitLab instance details
GITLAB_URL="http://gitlab.local"
ADMIN_TOKEN="YOUR_ADMIN_PERSONAL_ACCESS_TOKEN_HERE"
USERNAME="testuser"
TOKEN_ID="123"  # Replace with your actual token ID

echo "=== Revoking Personal Access Token ==="

# Get user ID first
USER_ID=$(curl -H "Authorization: Bearer $ADMIN_TOKEN" \
     -H "Content-Type: application/json" \
     "$GITLAB_URL/api/v4/users?username=$USERNAME" \
     -s | jq -r '.[0].id')

echo "User ID: $USER_ID"

# Revoke the token
echo "Revoking token ID: $TOKEN_ID"
curl -X DELETE \
     -H "Authorization: Bearer $ADMIN_TOKEN" \
     -H "Content-Type: application/json" \
     "$GITLAB_URL/api/v4/users/$USER_ID/personal_access_tokens/$TOKEN_ID" \
     -w "\nHTTP Status: %{http_code}\n" \
     -s

echo ""
echo "=== Token should now be revoked ==="