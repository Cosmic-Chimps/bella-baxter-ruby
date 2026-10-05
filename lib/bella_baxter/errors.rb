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

  # #1050 — a secrets read that presented X-E2E-Public-Key got back something other than an envelope
  # that decrypts with this client's key. Refused, never returned: there is no plaintext fallback.
  #
  # +code+ is the stable, cross-SDK contract (apps/sdk/SDK_CONTRACT.md, "a presented key requires an
  # envelope"); the message names the request path and the code, never the body, ciphertext or a key.
  # A DecryptionError subclass so code that already rescues DecryptionError keeps catching it.
  class E2EEResponseError < DecryptionError
    # The 2xx answer was not an `"encrypted": true` envelope (plain secrets, or not JSON at all).
    PLAINTEXT_RESPONSE = "e2ee-plaintext-response"
    # The envelope was malformed, tampered with (GCM tag), or encrypted to a different key.
    DECRYPTION_FAILED  = "e2ee-decryption-failed"

    attr_reader :code, :path

    def initialize(code, path)
      @code = code
      @path = path
      what = code == PLAINTEXT_RESPONSE ? "expected but plaintext received" : "could not be decrypted"
      super("E2EE response #{what} for #{path}; refusing it (#{code})")
    end

    def self.plaintext(path) = new(PLAINTEXT_RESPONSE, path)

    def self.decryption_failed(path) = new(DECRYPTION_FAILED, path)
  end

  # Raised when required configuration is missing.
  class ConfigurationError < Error; end

  # Raised when webhook signature verification fails due to a malformed header
  # or a timestamp that exceeds the tolerance window.
  class WebhookSignatureError < Error; end
end
