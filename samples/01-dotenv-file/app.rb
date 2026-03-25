# frozen_string_literal: true
#
# Sample 01: Ruby app — reads secrets from a .env file written by bella.
#
# Pattern: bella writes the .env file once; your app loads it on startup.
# No network calls at runtime — the secrets are already on disk.
#
# Workflow:
#   bella secrets get -p my-project -e production -o .env
#   bundle exec ruby app.rb

require "dotenv/load"

port    = ENV.fetch("PORT", "3000").to_i
db_url  = ENV.fetch("DATABASE_URL", "(not set)")
api_key = ENV.fetch("EXTERNAL_API_KEY", "(not set)")

puts "=== Bella Baxter: .env file sample (Ruby) ==="
puts ""
puts "PORT         : #{port}"
puts "DATABASE_URL : #{db_url.length > 8 ? "#{db_url[0, 8]}***" : db_url}"
puts "API_KEY      : #{api_key.length > 4 ? "#{api_key[0, 4]}***" : "(not set)"}"
puts ""
puts "All env vars loaded from .env file written by:"
puts "  bella secrets get -p my-project -e production -o .env"
