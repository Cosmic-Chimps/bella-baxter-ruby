# frozen_string_literal: true

module BellaBaxter
  # Options for constructing a Client.
  Configuration = Struct.new(
    :baxter_url,    # Base URL of the Baxter API (e.g. "https://baxter.example.com")
    :api_key,       # Bella API key in format bax-{keyId}-{signingSecret}
    :timeout,       # HTTP timeout in seconds (default: 10)
    keyword_init: true
  ) do
    def initialize(**)
      super
      self.timeout ||= 10
    end
  end

  # Response from GET /api/v1/projects/:project/environments/:env/secrets
  AllSecretsResponse = Struct.new(
    :environment_slug,   # String
    :environment_name,   # String
    :secrets,            # Hash<String, String> — all secrets for the environment
    :version,            # Integer — monotonically increasing (unix timestamp of last mutation)
    :last_modified,      # String — ISO-8601 timestamp
    keyword_init: true
  )

  # Response from GET .../secrets/version (lightweight version check)
  SecretsVersionResponse = Struct.new(
    :environment_slug,
    :version,
    :last_modified,
    keyword_init: true
  )

  # Metadata for a single TOTP key stored in an environment.
  # Returned by Client#list_totp_keys.
  TotpKeyInfo = Struct.new(
    :name,          # String — key name
    :issuer,        # String | nil — e.g. "GitHub"
    :account_name,  # String | nil — e.g. "user@example.com"
    :algorithm,     # String — e.g. "SHA1"
    :digits,        # Integer — code length (usually 6)
    :period,        # Integer — rotation period in seconds (usually 30)
    keyword_init: true
  )
end
