#!/bin/bash

# Replace these values with your actual GitLab instance details
GITLAB_URL="http://gitlab.local"
ADMIN_TOKEN="YOUR_ADMIN_PERSONAL_ACCESS_TOKEN_HERE"
USERNAME="testuser"

echo "=== Getting Token ID for user: $USERNAME ==="

# Get user ID first
USER_ID=$(curl -H "Authorization: Bearer $ADMIN_TOKEN" \
     -H "Content-Type: application/json" \
     "$GITLAB_URL/api/v4/users?username=$USERNAME" \
     -s | jq -r '.[0].id')

echo "User ID: $USER_ID"

# Get personal access tokens for the user
echo "Fetching personal access tokens..."
curl -H "Authorization: Bearer $ADMIN_TOKEN" \
     -H "Content-Type: application/json" \
     "$GITLAB_URL/api/v4/users/$USER_ID/personal_access_tokens" \
     -s | jq '.[] | {id: .id, name: .name, created_at: .created_at, expires_at: .expires_at}'

echo ""
echo "=== Note the token ID for the next step ==="