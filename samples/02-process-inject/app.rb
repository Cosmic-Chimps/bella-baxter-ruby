# frozen_string_literal: true
#
# Sample 02: Ruby app — reads secrets injected into ENV by bella run.
#
# Bella runs your app as a subprocess and injects secrets as env vars.
# Your code reads them via ENV — no SDK, no file, no latency.
#
# Workflow:
#   bella run -p my-project -e production -- ruby app.rb

port    = ENV.fetch("PORT", "3000").to_i
db_url  = ENV.fetch("DATABASE_URL", "(not set)")
api_key = ENV.fetch("EXTERNAL_API_KEY", "(not set)")
project = ENV.fetch("BELLA_BAXTER_PROJECT", "unknown")
env     = ENV.fetch("BELLA_BAXTER_ENV", "unknown")

puts "=== Bella Baxter: process-inject sample (Ruby) ==="
puts ""
puts "Project      : #{project}"
puts "Environment  : #{env}"
puts ""
puts "PORT         : #{port}"
puts "DATABASE_URL : #{db_url.length > 8 ? "#{db_url[0, 8]}***" : db_url}"
puts "API_KEY      : #{api_key.length > 4 ? "#{api_key[0, 4]}***" : "(not set)"}"
puts ""
puts "Secrets were injected by:"
puts "  bella run -p my-project -e production -- ruby app.rb"
