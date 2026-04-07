# frozen_string_literal: true

require "faraday"
require "json"

module BellaBaxter
  # Faraday middleware that transparently adds E2EE to GET /secrets requests.
  #
  # On outbound: adds X-E2E-Public-Key header so the server encrypts the response.
  # On inbound:  decrypts the encrypted payload and reconstructs a normal secrets response.
  class E2EEFaradayMiddleware < Faraday::Middleware
    def initialize(app, key_pair: nil, on_wrapped_dek_received: nil)
      super(app)
      @e2ee = key_pair || E2EE::KeyPair.new
      @on_wrapped_dek_received = on_wrapped_dek_received
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

        if @on_wrapped_dek_received
          wrapped_dek = resp_env.response_headers["X-Bella-Wrapped-Dek"] ||
                        resp_env.response_headers["x-bella-wrapped-dek"]
          if wrapped_dek
            lease_expires = resp_env.response_headers["X-Bella-Lease-Expires"] ||
                            resp_env.response_headers["x-bella-lease-expires"]
            path        = env.url.path
            project_slug = path[%r{/projects/([^/]+)}, 1] || ""
            env_slug     = path[%r{/environments/([^/]+)}, 1] || ""
            @on_wrapped_dek_received.call(project_slug, env_slug, wrapped_dek, lease_expires)
          end
        end
      end
    end
  end
end
