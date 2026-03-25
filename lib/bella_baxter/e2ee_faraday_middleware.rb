# frozen_string_literal: true

require "faraday"
require "json"

module BellaBaxter
  # Faraday middleware that transparently adds E2EE to GET /secrets requests.
  #
  # On outbound: adds X-E2E-Public-Key header so the server encrypts the response.
  # On inbound:  decrypts the encrypted payload and reconstructs a normal secrets response.
  class E2EEFaradayMiddleware < Faraday::Middleware
    def initialize(app)
      super
      @e2ee = E2EE::KeyPair.new
    end

    def call(env)
      is_secrets_get = env.method == :get && env.url.path.end_with?("/secrets")

      if is_secrets_get
        env.request_headers["X-E2E-Public-Key"] = @e2ee.public_key_b64
      end

      @app.call(env).on_complete do |resp_env|
        next unless is_secrets_get && resp_env.status == 200

        data = JSON.parse(resp_env.body)
        next unless data["encrypted"]

        decrypted = @e2ee.decrypt_raw(data)
        if decrypted.is_a?(Hash) && decrypted.key?("secrets") && decrypted["secrets"].is_a?(Hash)
          resp_env[:body] = JSON.generate(decrypted)
        else
          secrets = @e2ee.decrypt(data)
          resp_env[:body] = JSON.generate(
            "secrets"         => secrets,
            "version"         => 0,
            "environmentSlug" => "",
            "environmentName" => "",
            "lastModified"    => ""
          )
        end
      end
    end
  end
end
