#!/bin/bash

# Replace with your GitLab instance details
GITLAB_URL="http://gitlab.local"
YOUR_TOKEN="YOUR_PERSONAL_ACCESS_TOKEN_HERE"

echo "=== Finding Your Own Token ID via GitLab API ==="

# Method 1: List your own personal access tokens
echo "1. Listing your personal access tokens..."
curl -H "Authorization: Bearer $YOUR_TOKEN" \
     -H "Content-Type: application/json" \
     "$GITLAB_URL/api/v4/user/personal_access_tokens" \
     -s | jq '.[] | {id: .id, name: .name, created_at: .created_at, expires_at: .expires_at}'

echo ""
echo "=== Analysis ==="
echo "This API endpoint returns token IDs for your own tokens only."
echo "You cannot access other users' token IDs through this method."