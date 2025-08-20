# Rails Console Script to test PersonalAccessToken.find() behavior
# Run this in your GitLab Rails console: rails console

puts "=== Testing PersonalAccessToken.find() with Non-existent IDs ==="

# Test 1: Find with existing token ID
existing_token = PersonalAccessToken.first
if existing_token
  puts "Existing token ID: #{existing_token.id}"
  
  begin
    found_token = PersonalAccessToken.find(existing_token.id)
    puts "✅ Found existing token: #{found_token.id}"
  rescue => e
    puts "❌ Error finding existing token: #{e.class} - #{e.message}"
  end
end

puts ""

# Test 2: Find with non-existent token ID
non_existent_id = 999999
puts "Testing with non-existent ID: #{non_existent_id}"

begin
  found_token = PersonalAccessToken.find(non_existent_id)
  puts "✅ Found token with non-existent ID (unexpected!): #{found_token.id}"
rescue ActiveRecord::RecordNotFound => e
  puts "❌ ActiveRecord::RecordNotFound: #{e.message}"
rescue => e
  puts "❌ Other error: #{e.class} - #{e.message}"
end

puts ""

# Test 3: Check what happens in the vulnerable code path
puts "=== Testing Vulnerable Code Path ==="

# Simulate the vulnerable JWT resolution
def simulate_jwt_resolution(token_id)
  begin
    pat = PersonalAccessToken.find(token_id)
    puts "✅ Token found: #{pat.id} (User: #{pat.user.username})"
    return pat
  rescue ActiveRecord::RecordNotFound => e
    puts "❌ Token not found: #{e.message}"
    return nil
  rescue => e
    puts "❌ Other error: #{e.class} - #{e.message}"
    return nil
  end
end

# Test with existing token
if existing_token
  puts "Testing with existing token ID: #{existing_token.id}"
  simulate_jwt_resolution(existing_token.id)
end

puts ""

# Test with non-existent token
puts "Testing with non-existent token ID: #{non_existent_id}"
result = simulate_jwt_resolution(non_existent_id)

puts ""
puts "=== Analysis ==="
puts "If PersonalAccessToken.find() raises ActiveRecord::RecordNotFound for non-existent IDs,"
puts "then random token ID guessing will fail and return nil."
puts "This means the JWT authentication will fail for guessed token IDs."