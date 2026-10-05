# frozen_string_literal: true

require "faraday"
require "json"
require_relative "errors"
require_relative "e2ee"

module BellaBaxter
  # Faraday middleware that transparently adds E2EE to the envelope-required secret reads.
  #
  # On outbound: adds X-E2E-Public-Key on every envelope-required read (#1162, +requires_envelope?+) so
  #              the server encrypts the response.
  # On inbound:  decrypts the envelope and hands the server's plaintext JSON on unchanged.
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
      # #1162 — the key is presented on EVERY envelope-required read (SDK_CONTRACT.md, "Rule: the key is
      # presented on every envelope-required read"), decided here by the one matcher, never per method.
      # From then on a 2xx that is not a decryptable envelope is an error (#1050), never a value.
      presented = self.class.requires_envelope?(env.method, env.url.path)

      env.request_headers["X-E2E-Public-Key"] = @e2ee.public_key_b64 if presented

      @app.call(env).on_complete do |resp_env|
        next unless presented && resp_env.status.between?(200, 299)

        path = env.url.path
        data = begin
          JSON.parse(resp_env.body.to_s)
        rescue JSON::ParserError
          raise E2EEResponseError.plaintext(path)
        end

        raise E2EEResponseError.plaintext(path) unless data.is_a?(Hash) && data["encrypted"] == true

        resp_env[:body] = decrypted_body(data, path)

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

    # The body handed on after decryption. The plaintext of every envelope-required read is the JSON the
    # server would have sent without a key (a secret item, an array of them, a {key: value} export,
    # ListGlobalSecretsResponse), so it is passed on byte for byte (#1162). Only getAllEnvironmentSecrets
    # keeps its legacy rescue: a server that encrypted just the flat {key: value} dict is re-wrapped as an
    # AllEnvironmentSecretsResponse. Any failure — a missing or undecodable field, a GCM tag that does not
    # verify (tampered), a key it was not encrypted to — is the one refusal, with the original as +cause+.
    def decrypted_body(data, path)
      plaintext = @e2ee.decrypt_plaintext(data)
      decrypted = JSON.parse(plaintext)
      return plaintext unless all_environment_secrets?(path)
      return plaintext if decrypted.is_a?(Hash) && decrypted["secrets"].is_a?(Hash)
      raise E2EEResponseError.decryption_failed(path) unless decrypted.is_a?(Hash)

      JSON.generate(
        "secrets"         => decrypted.transform_values(&:to_s),
        "version"         => 0,
        "environmentSlug" => "",
        "environmentName" => "",
        "lastModified"    => ""
      )
    rescue E2EEResponseError
      raise
    rescue StandardError
      raise E2EEResponseError.decryption_failed(path)
    end

    # .../api/v1/projects/{p}/environments/{e}/secrets — getAllEnvironmentSecrets.
    def all_environment_secrets?(path)
      marker = "/api/v1/projects/"
      i = path.to_s.index(marker) or return false
      segs = path[(i + marker.length)..].split("/", -1)
      segs.length == 4 && segs[1] == "environments" && segs[3] == "secrets"
    end
  end
end
