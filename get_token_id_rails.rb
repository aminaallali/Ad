# Rails Console Script to get Token ID
# Run this in your GitLab Rails console: rails console

puts "=== Getting Token ID via Rails Console ==="

# Find the user
user = User.find_by(username: 'testuser')
puts "User: #{user.username} (ID: #{user.id})"

# Find the personal access token
token = PersonalAccessToken.find_by(user: user, name: 'Test Token')
if token
  puts "Token ID: #{token.id}"
  puts "Token Name: #{token.name}"
  puts "Token State: revoked=#{token.revoked?}, expired=#{token.expired?}, active=#{token.active?}"
  puts "Token Expires At: #{token.expires_at}"
else
  puts "Token not found!"
end

puts "=== Use this Token ID in the JWT payload ==="