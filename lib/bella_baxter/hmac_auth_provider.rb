# frozen_string_literal: true

require "openssl"
require "digest"
require "time"
require "uri"

module BellaBaxter
  # Kiota AuthenticationProvider that signs every request with HMAC-SHA256.
  #
  # Reads the bax-{keyId}-{signingSecret} API key and adds:
  #   X-Bella-Key-Id, X-Bella-Timestamp, X-Bella-Signature
  class HmacAuthProvider
    def initialize(api_key, bella_client: 'bella-ruby-sdk', app_client: nil)
      parts = api_key.split("-", 3)
      unless parts.length == 3 && parts[0] == "bax"
        raise InvalidApiKeyError, "api_key must be in format bax-{keyId}-{signingSecret}"
      end

      @key_id         = parts[1]
      @signing_secret = [parts[2]].pack("H*")
      @bella_client   = bella_client
      @app_client     = app_client || ENV['BELLA_BAXTER_APP_CLIENT']
    end

    def authenticate_request(request, _additional_context = {})
      Fiber.new do
        method    = request.http_method.to_s.upcase
        uri       = URI.parse(request.uri.to_s)
        path      = uri.path
        query     = sorted_query(uri.query)
        body      = request.content.to_s
        timestamp = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
        body_hash = Digest::SHA256.hexdigest(body)
        sts       = "#{method}\n#{path}\n#{query}\n#{timestamp}\n#{body_hash}"
        signature = OpenSSL::HMAC.hexdigest("SHA256", @signing_secret, sts)

        request.headers.try_add("X-Bella-Key-Id",    @key_id)
        request.headers.try_add("X-Bella-Timestamp", timestamp)
        request.headers.try_add("X-Bella-Signature", signature)
        request.headers.try_add("X-Bella-Client",    @bella_client)
        request.headers.try_add("X-App-Client",      @app_client) if @app_client
      end
    end

    private

    def sorted_query(raw)
      return "" if raw.nil? || raw.empty?

      URI.decode_www_form(raw).sort_by { |k, _| k }
        .map { |k, v| "#{URI.encode_www_form_component(k)}=#{URI.encode_www_form_component(v)}" }
        .join("&")
    end
  end
end
