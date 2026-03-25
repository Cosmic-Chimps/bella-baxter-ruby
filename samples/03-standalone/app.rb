# frozen_string_literal: true
#
# Sample 03: Ruby script — pulls secrets via the BellaBaxter SDK.
#
# Workflow (API key mode — the easiest):
#   bella exec --app ruby-03-standalone -- bundle exec ruby app.rb
#
# bella exec injects BELLA_BAXTER_API_KEY, BELLA_BAXTER_URL,
# BELLA_BAXTER_PROJECT, and BELLA_BAXTER_ENV automatically.

require "bella_baxter"

client = BellaBaxter::Client.from_env

secrets = client.pull_secrets
puts "=== Bella Baxter: SDK standalone sample (Ruby) ==="
puts ""
puts "Loaded #{secrets.size} secret(s)"
puts ""

db_url = secrets["DATABASE_URL"] || "(not set)"
api_key = secrets["EXTERNAL_API_KEY"] || "(not set)"
port = secrets["PORT"] || "(not set)"

puts "PORT         : #{port}"
puts "DATABASE_URL : #{db_url.length > 8 ? "#{db_url[0, 8]}***" : db_url}"
puts "API_KEY      : #{api_key.length > 4 ? "#{api_key[0, 4]}***" : "(not set)"}"
puts ""
puts "Secrets pulled live from Bella via BellaBaxter::Client.from_env"
