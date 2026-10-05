# frozen_string_literal: true

require "faraday"
require "json"
require_relative "errors"
require_relative "e2ee"

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

    # #1050 — the GETs whose 2xx body the server encrypts to a presented key: every read that carries
    # secret VALUES (apps/sdk/SDK_CONTRACT.md, "Which Endpoints Support E2EE"). Everything else under
    # /secrets (…/version, …/manifest, …/hash, …/{key}/metadata, writes) is plain JSON by design and must
    # never be refused. One place, so the rule and the table cannot drift apart inside this SDK.
    def self.requires_envelope?(method, path)
      return false unless method.to_s.downcase == "get"

      marker = "/api/v1/projects/"
      i = path.to_s.index(marker) or return false
      _project, *rest = path[(i + marker.length)..].split("/", -1)

      return true if rest == ["secrets"]
      return false unless rest.length >= 3 && rest[0] == "environments"

      tail = rest[2..]
      return true if tail == ["secrets"] || tail == ["secrets", "export"]
      return false unless tail.length >= 3 && tail[0] == "providers" && tail[2] == "secrets"

      provider_tail = tail[3..]
      case provider_tail.length
      when 0 then true
      when 1 then provider_tail[0] != "hash" && !provider_tail[0].empty?
      when 3 then provider_tail[1] == "versions" && provider_tail[2].match?(/\A\d+\z/)
      else false
      end
    end

    def call(env)
      is_secrets_get = env.method == :get && env.url.path.end_with?("/secrets")

      if is_secrets_get
        env.request_headers["X-E2E-Public-Key"] = @e2ee.public_key_b64
      end

      # The key was presented on a read the server always encrypts: from here a 2xx that is not a
      # decryptable envelope is an error (#1050), never a value.
      envelope_required = is_secrets_get && self.class.requires_envelope?(env.method, env.url.path)

      @app.call(env).on_complete do |resp_env|
        next unless is_secrets_get && resp_env.status.between?(200, 299)

        path = env.url.path
        data = begin
          JSON.parse(resp_env.body.to_s)
        rescue JSON::ParserError
          raise E2EEResponseError.plaintext(path) if envelope_required

          next
        end

        unless data.is_a?(Hash) && data["encrypted"] == true
          raise E2EEResponseError.plaintext(path) if envelope_required

          next
        end

        decrypted, secrets = decrypt_envelope(data, path)
        if decrypted.is_a?(Hash) && decrypted.key?("secrets") && decrypted["secrets"].is_a?(Hash)
          resp_env[:body] = JSON.generate(decrypted)
        else
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

    private

    # Both views of one envelope: the raw decrypted JSON and the flattened secrets hash. Any failure —
    # a missing or undecodable field, a GCM tag that does not verify (tampered), a key it was not
    # encrypted to — is the one refusal below, with the original error kept as +cause+.
    def decrypt_envelope(data, path)
      [@e2ee.decrypt_raw(data), @e2ee.decrypt(data)]
    rescue StandardError
      raise E2EEResponseError.decryption_failed(path)
    end
  end
end
