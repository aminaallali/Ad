# Rails Console Script to find JWT secret
# Run this in your GitLab Rails console: rails console

puts "=== Finding GitLab JWT Secret Key ==="

# Method 1: Check GitLab settings
begin
  secret = Gitlab::CurrentSettings.jwt_secret
  puts "JWT Secret from settings: #{secret}"
rescue => e
  puts "Could not get JWT secret from settings: #{e.message}"
end

# Method 2: Check Rails secret key base
begin
  secret = Rails.application.secrets.secret_key_base
  puts "Rails secret key base: #{secret}"
rescue => e
  puts "Could not get Rails secret: #{e.message}"
end

# Method 3: Check environment variables
puts "JWT_SECRET env var: #{ENV['JWT_SECRET']}"
puts "SECRET_KEY_BASE env var: #{ENV['SECRET_KEY_BASE']}"

# Method 4: Check GitLab configuration files
puts ""
puts "=== Check these files for JWT configuration ==="
puts "1. config/gitlab.yml"
puts "2. config/secrets.yml"
puts "3. .gitlab-secrets.json (if using GDK)"

puts ""
puts "=== Common locations for JWT secret ==="
puts "GDK: .gitlab-secrets.json"
puts "Docker: Environment variables"
puts "Self-hosted: config/gitlab.yml or environment variables"