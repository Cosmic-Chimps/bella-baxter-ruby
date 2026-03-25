# frozen_string_literal: true

require "openssl"

module BellaBaxter
  # Verifies the X-Bella-Signature header on incoming Bella Baxter webhook requests.
  #
  # Signature format:  X-Bella-Signature: t={unix_epoch_seconds},v1={hmac_sha256_hex}
  # Signing input:     "{t}.{rawBodyJson}"  (UTF-8)
  # HMAC key:          the raw signing secret string (full whsec-xxx value, UTF-8 encoded)
  module WebhookSignature
    DEFAULT_TOLERANCE = 300

    # Verifies the X-Bella-Signature header on an incoming webhook.
    #
    # @param secret [String] the whsec-xxx signing secret
    # @param signature_header [String] value of X-Bella-Signature header
    # @param raw_body [String] raw request body string (UTF-8)
    # @param tolerance [Integer] max age in seconds (default 300)
    # @return [Boolean] true if the signature is valid and the timestamp is within tolerance
    # @raise [WebhookSignatureError] if the header is malformed or the timestamp is out of tolerance
    def self.verify(secret:, signature_header:, raw_body:, tolerance: DEFAULT_TOLERANCE)
      parts   = signature_header.to_s.split(",")
      t_part  = parts.find { |p| p.start_with?("t=") }
      v1_part = parts.find { |p| p.start_with?("v1=") }

      raise BellaBaxter::WebhookSignatureError, "Malformed X-Bella-Signature header: missing t= or v1=" \
        if t_part.nil? || v1_part.nil?

      begin
        timestamp = Integer(t_part[2..], 10)
      rescue ArgumentError
        raise BellaBaxter::WebhookSignatureError, "Malformed X-Bella-Signature header: t= is not a valid integer"
      end

      v1  = v1_part[3..]
      age = Time.now.utc.to_i - timestamp

      raise BellaBaxter::WebhookSignatureError,
        "Webhook timestamp is stale or in the future (age=#{age}s, tolerance=#{tolerance}s)" \
        if age.abs > tolerance

      signing_input = "#{timestamp}.#{raw_body}"
      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, signing_input)

      secure_compare(expected, v1)
    end
    private_class_method def self.secure_compare(a, b)
      # Constant-time comparison: XOR every byte pair and OR the results.
      # Returning false on a length mismatch is safe here because `a` is always
      # the 64-character HMAC-SHA256 hex digest — its length is not secret.
      return false unless a.bytesize == b.bytesize

      result = 0
      a.bytes.zip(b.bytes) { |x, y| result |= x ^ y }
      result.zero?
    end
  end
end
