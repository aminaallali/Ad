# Rails Console Script to create JWT token using GitLab's built-in functionality
# Run this in your GitLab Rails console: rails console

puts "=== Using GitLab's Built-in JWT Token Functionality ==="

# Find the user and token
user = User.find_by(username: 'testuser')
token = PersonalAccessToken.find_by(user: user, name: 'Test Token')

if token
  puts "Token ID: #{token.id}"
  puts "Token State: revoked=#{token.revoked?}, expired=#{token.expired?}, active=#{token.active?}"
  
  # Create JWT token using GitLab's JWTToken class
  jwt_token = Gitlab::JWTToken.new
  jwt_token['token'] = token.id  # Embed the Personal Access Token ID
  
  puts ""
  puts "JWT Token:"
  puts jwt_token.encoded
  
  puts ""
  puts "=== Use this JWT token in the Authorization header ==="
  puts "Authorization: Bearer #{jwt_token.encoded}"
  
  puts ""
  puts "=== Test this token even after revoking the original Personal Access Token ==="
else
  puts "Token not found!"
end