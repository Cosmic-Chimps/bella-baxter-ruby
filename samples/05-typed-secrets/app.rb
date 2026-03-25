# Typed Secrets sample — one secret per Bella type:
#   String → external_api_key
#   Int    → port
#   Bool   → enable_features
#   Uri    → database_url   ← URI object
#   JSON   → app_config     ← parsed into AppConfigShape struct
#   GUID   → app_id
#
# Workflow:
#   bella secrets generate ruby -p my-project -e production -o secrets.rb
#   bella exec -- bundle exec ruby app.rb

require 'dotenv/load'
require_relative 'secrets'

cfg = AppSecrets.app_config

puts "=== Bella Baxter: Typed Secrets (Ruby) ==="
puts
puts "String  EXTERNAL_API_KEY : #{AppSecrets.external_api_key[0, 4]}***"
puts "Int     PORT             : #{AppSecrets.port}  ← class: #{AppSecrets.port.class}"
puts "Bool    ENABLE_FEATURES  : #{AppSecrets.enable_features}  ← class: #{AppSecrets.enable_features.class}"
puts "Uri     DATABASE_URL     : host=#{AppSecrets.database_url.host}  ← scheme: #{AppSecrets.database_url.scheme}"
puts "JSON    APP_CONFIG       : #{cfg}"
puts "           .setting1    : #{cfg.setting1.inspect}  ← String"
puts "           .setting2    : #{cfg.setting2.inspect}  ← Integer"
puts "GUID    APP_ID           : #{AppSecrets.app_id}"
puts
puts "No raw ENV[] calls — secrets are typed, validated, and structured."
