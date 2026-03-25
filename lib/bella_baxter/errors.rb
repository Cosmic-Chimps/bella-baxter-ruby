# frozen_string_literal: true

module BellaBaxter
  class Error < StandardError; end

  # Raised when the API key format is invalid (must be bax-{keyId}-{signingSecret}).
  class InvalidApiKeyError < Error; end

  # Raised when the server returns a non-2xx response.
  class ApiError < Error
    attr_reader :status, :body

    def initialize(status, body)
      @status = status
      @body   = body
      super("Bella Baxter API error #{status}: #{body}")
    end
  end

  # Raised when E2EE decryption fails.
  class DecryptionError < Error; end

  # Raised when required configuration is missing.
  class ConfigurationError < Error; end

  # Raised when webhook signature verification fails due to a malformed header
  # or a timestamp that exceeds the tolerance window.
  class WebhookSignatureError < Error; end
end
