#!/usr/bin/env ruby

require 'jwt'
require 'json'

# Configuration
TOKEN_ID = 123  # Replace with your actual token ID from Step 4
GITLAB_SECRET = 'your-gitlab-secret-key'  # You'll need to find this

puts "=== Creating JWT Token with Personal Access Token ID ==="

# Create the JWT payload
payload = {
  'token' => TOKEN_ID,  # This is the Personal Access Token ID
  'iat' => Time.now.to_i,
  'exp' => Time.now.to_i + 3600  # Expires in 1 hour
}

puts "JWT Payload:"
puts JSON.pretty_generate(payload)

# Create the JWT token
# Note: You'll need to find the correct secret key for your GitLab instance
jwt_token = JWT.encode(payload, GITLAB_SECRET, 'HS256')

puts ""
puts "JWT Token:"
puts jwt_token

puts ""
puts "=== Use this JWT token in the Authorization header ==="
puts "Authorization: Bearer #{jwt_token}"