# frozen_string_literal: true

require_relative "lib/bella_baxter/version"

Gem::Specification.new do |spec|
  spec.name        = "bella_baxter"
  spec.version     = BellaBaxter::VERSION
  spec.authors     = ["Cosmic Chimps"]
  spec.email       = ["team@cosmicchimps.com"]
  spec.summary     = "Ruby SDK for the Bella Baxter secret management platform"
  spec.description = <<~DESC
    Load secrets from Bella Baxter into your Ruby or Rails application.
    Uses Kiota-generated client with HMAC-SHA256 authentication and transparent
    end-to-end encryption via Faraday middleware. Supports Rails auto-loading
    via Railtie and direct ENV injection.
  DESC
  spec.homepage    = "https://github.com/cosmic-chimps/bella-baxter"
  spec.license     = "ELv2"

  spec.required_ruby_version = ">= 4.0"

  spec.files = Dir[
    "lib/**/*.rb",
    "README.md",
    "CHANGELOG.md"
  ]
  spec.require_paths = ["lib"]

  spec.add_dependency "microsoft_kiota_abstractions",      "~> 0.14"
  spec.add_dependency "microsoft_kiota_faraday",            "~> 0.15"
  spec.add_dependency "microsoft_kiota_serialization_json", "~> 0.9"
  spec.add_dependency "base64"

  # Zero development dependencies — all stdlib (openssl, net/http, json, base64, uri)
  spec.add_development_dependency "rake",      "~> 13.0"
  spec.add_development_dependency "rspec",     "~> 3.12"
  spec.add_development_dependency "webmock",   "~> 3.23"
  spec.add_development_dependency "railties",  ">= 7.0"
end
