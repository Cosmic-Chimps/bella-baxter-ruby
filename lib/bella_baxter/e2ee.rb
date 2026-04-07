# frozen_string_literal: true

require "openssl"
require "base64"
require "json"

module BellaBaxter
  # End-to-end encryption using ECDH-P256-HKDF-SHA256-AES256GCM.
  #
  # The client generates a P-256 keypair on initialization and sends
  # +X-E2E-Public-Key+ with every secrets request. The server encrypts
  # the response payload; this class transparently decrypts it.
  #
  # No extra gems required — uses Ruby's built-in +openssl+ stdlib.
  module E2EE
    class KeyPair
      # Base64-encoded DER/SPKI public key to send as X-E2E-Public-Key header.
      attr_reader :public_key_b64

      def initialize
        @ec = OpenSSL::PKey::EC.generate("prime256v1")

        # Export public key in SubjectPublicKeyInfo (SPKI/DER) format — what the server expects.
        # public_to_der is available in Ruby 3.0+ (openssl gem 3.x) via OpenSSL::PKey::PKey.
        @public_key_b64 = Base64.strict_encode64(@ec.public_to_der)
      end

      # Create a KeyPair from a PKCS#8 PEM private key (ZKE persistent device key).
      # Use this instead of KeyPair.new for ZKE mode.
      # Obtain a key with: bella auth setup
      def self.from_pem(pem)
        private_key    = OpenSSL::PKey::EC.new(pem)
        public_key_b64 = Base64.strict_encode64(private_key.public_to_der)

        instance = allocate
        instance.send(:initialize_from_key, private_key, public_key_b64)
        instance
      end

      # Decrypt a response payload.
      #
      # @param payload [Hash] Parsed JSON with keys:
      #   encrypted, algorithm, serverPublicKey, nonce, tag, ciphertext
      # @return [Hash] Decrypted secrets hash
      # @raise [BellaBaxter::DecryptionError]
      def decrypt(payload)
        return payload unless payload["encrypted"] == true

        server_key_der  = Base64.strict_decode64(payload["serverPublicKey"])
        nonce           = Base64.strict_decode64(payload["nonce"])
        tag             = Base64.strict_decode64(payload["tag"])
        ciphertext      = Base64.strict_decode64(payload["ciphertext"])

        # Load server public key from SPKI DER and compute ECDH shared secret.
        # OpenSSL::PKey.read handles SPKI DER for all key types (Ruby 4.0 / openssl gem 4.x).
        server_key      = OpenSSL::PKey.read(server_key_der)
        shared_secret   = @ec.derive(server_key)

        # HKDF-SHA256: extract + expand to 32-byte AES key.
        key             = hkdf_sha256(shared_secret, 32)

        # AES-256-GCM decrypt.
        cipher          = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.decrypt
        cipher.key      = key
        cipher.iv       = nonce
        cipher.auth_tag = tag
        cipher.auth_data = ""

        plaintext = cipher.update(ciphertext) + cipher.final
        parsed = JSON.parse(plaintext)

        # Three possible server response shapes:
        #   1. Full AllEnvironmentSecretsResponse: {"environmentSlug":..., "secrets":{...}, ...}
        #   2. Array of SecretItem:                [{"key":"K","value":"V"}, ...]
        #   3. Legacy flat dict:                   {"K":"V", ...}
        if parsed.is_a?(Hash) && parsed.key?("secrets") && parsed["secrets"].is_a?(Hash)
          parsed["secrets"].transform_values(&:to_s)
        elsif parsed.is_a?(Array)
          parsed.each_with_object({}) do |item, h|
            h[item["key"]] = item.fetch("value", "").to_s if item["key"]
          end
        else
          parsed
        end
      rescue OpenSSL::Cipher::CipherError => e
        raise BellaBaxter::DecryptionError, "AES-GCM decryption failed: #{e.message}"
      rescue JSON::ParserError => e
        raise BellaBaxter::DecryptionError, "Decrypted payload is not valid JSON: #{e.message}"
      end

      # Decrypt a response payload, returning the raw parsed JSON without transformation.
      #
      # Unlike +decrypt+, this preserves the full server response shape (including
      # +environmentSlug+, +version+, +lastModified+, etc.).
      #
      # @param payload [Hash] Parsed JSON encrypted payload.
      # @return [Hash] Full decrypted + parsed JSON hash.
      # @raise [BellaBaxter::DecryptionError]
      def decrypt_raw(payload)
        return payload unless payload["encrypted"] == true

        server_key_der = Base64.strict_decode64(payload["serverPublicKey"])
        nonce          = Base64.strict_decode64(payload["nonce"])
        tag            = Base64.strict_decode64(payload["tag"])
        ciphertext     = Base64.strict_decode64(payload["ciphertext"])

        server_key   = OpenSSL::PKey.read(server_key_der)
        shared_secret = @ec.derive(server_key)
        key          = hkdf_sha256(shared_secret, 32)

        cipher           = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.decrypt
        cipher.key       = key
        cipher.iv        = nonce
        cipher.auth_tag  = tag
        cipher.auth_data = ""

        plaintext = cipher.update(ciphertext) + cipher.final
        JSON.parse(plaintext)
      rescue OpenSSL::Cipher::CipherError => e
        raise BellaBaxter::DecryptionError, "AES-GCM decryption failed: #{e.message}"
      rescue JSON::ParserError => e
        raise BellaBaxter::DecryptionError, "Decrypted payload is not valid JSON: #{e.message}"
      end

      private

      # Shared setup used by from_pem — sets the same instance variables as initialize.
      def initialize_from_key(ec_key, public_key_b64)
        @ec             = ec_key
        @public_key_b64 = public_key_b64
      end

      # HKDF (RFC 5869) using HMAC-SHA256. Salt is 32 zero bytes (matches server).
      def hkdf_sha256(ikm, length)
        salt = "\x00" * 32
        info = "bella-e2ee-v1"
        prk  = OpenSSL::HMAC.digest("SHA256", salt, ikm)

        t   = "".b
        okm = "".b
        n   = (length.to_f / 32).ceil

        n.times do |i|
          t   = OpenSSL::HMAC.digest("SHA256", prk, t + info + (i + 1).chr)
          okm += t
        end

        okm[0, length]
      end
    end
  end
end
