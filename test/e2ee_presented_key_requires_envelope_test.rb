# frozen_string_literal: true

# Issue #1050 (b) — once the SDK has presented X-E2E-Public-Key on a read the server always encrypts, a
# 2xx answer that is not a decryptable envelope is REFUSED with BellaBaxter::E2EEResponseError, never
# returned as secrets (apps/sdk/SDK_CONTRACT.md, "Rule: a presented key requires an envelope").
#
# A misbehaving stub over real HTTP (a TCPServer, the net_http adapter) answers the presented key with a
# valid envelope, plaintext, a tampered envelope and an envelope to another key. Drives the Faraday
# middleware — the SDK's only E2EE path — directly, so it runs without the generated Kiota client:
#   ruby -Ilib test/e2ee_presented_key_requires_envelope_test.rb
# Keys are generated per run; no key material is committed.

require "minitest/autorun"
require "base64"
require "json"
require "openssl"
require "socket"
require "faraday"
require_relative "../lib/bella_baxter/errors"
require_relative "../lib/bella_baxter/e2ee"
require_relative "../lib/bella_baxter/e2ee_faraday_middleware"

class E2EEPresentedKeyRequiresEnvelopeTest < Minitest::Test
  SECRETS_PATH  = "/api/v1/projects/contract-project/environments/contract-env/secrets"
  SENTINEL_KEY   = "BELLA_KEY_CONTRACT"
  SENTINEL_VALUE = "the-registered-device-key-was-used"
  PLAINTEXT = {
    "environmentSlug" => "contract-env",
    "environmentName" => "contract-env",
    "secrets"         => { SENTINEL_KEY => SENTINEL_VALUE },
    "version"         => 1,
    "lastModified"    => "2026-10-04T00:00:00Z"
  }.freeze

  Error = BellaBaxter::E2EEResponseError

  # ── The four contract cases on getAllEnvironmentSecrets ───────────────────────

  def test_a_valid_envelope_to_the_presented_key_is_decrypted
    with_stub(->(req) { [200, encrypt_for(req[:presented], JSON.generate(PLAINTEXT))] }) do |conn, requests|
      body = JSON.parse(conn.get(SECRETS_PATH).body)
      assert_equal SENTINEL_VALUE, body["secrets"][SENTINEL_KEY]
      refute_nil requests.last[:presented], "the read presented no X-E2E-Public-Key"
    end
  end

  def test_plaintext_after_presenting_the_key_is_refused
    with_stub(->(_req) { [200, PLAINTEXT] }) do |conn, _|
      error = assert_raises(Error) { conn.get(SECRETS_PATH) }
      assert_equal Error::PLAINTEXT_RESPONSE, error.code
      assert_equal "E2EE response expected but plaintext received for #{SECRETS_PATH}; " \
                   "refusing it (e2ee-plaintext-response)", error.message
      refute_includes error.message, SENTINEL_VALUE
    end
  end

  def test_a_tampered_envelope_is_refused
    tamper = lambda do |req|
      envelope = encrypt_for(req[:presented], JSON.generate(PLAINTEXT))
      bytes = Base64.strict_decode64(envelope["ciphertext"]).bytes
      bytes[0] ^= 0x01
      [200, envelope.merge("ciphertext" => Base64.strict_encode64(bytes.pack("C*")))]
    end
    with_stub(tamper) do |conn, _|
      error = assert_raises(Error) { conn.get(SECRETS_PATH) }
      assert_equal Error::DECRYPTION_FAILED, error.code
      assert_equal "E2EE response could not be decrypted for #{SECRETS_PATH}; " \
                   "refusing it (e2ee-decryption-failed)", error.message
      refute_nil error.cause, "the underlying failure should be kept as the cause"
    end
  end

  def test_an_envelope_to_another_key_is_refused
    other = Base64.strict_encode64(OpenSSL::PKey::EC.generate("prime256v1").public_to_der)
    with_stub(->(_req) { [200, encrypt_for(other, JSON.generate(PLAINTEXT))] }) do |conn, _|
      error = assert_raises(Error) { conn.get(SECRETS_PATH) }
      assert_equal Error::DECRYPTION_FAILED, error.code
    end
  end

  # ── The edges of the same rule ───────────────────────────────────────────────

  def test_a_non_json_body_on_an_envelope_required_read_is_plaintext
    # What a key-less export looks like (a dotenv file): with the key presented it must be an envelope.
    with_stub(->(_req) { [200, "#{SENTINEL_KEY}=#{SENTINEL_VALUE}\n"] }) do |conn, _|
      error = assert_raises(Error) { conn.get(SECRETS_PATH) }
      assert_equal Error::PLAINTEXT_RESPONSE, error.code
    end
  end

  def test_an_envelope_missing_a_field_is_a_decryption_failure
    strip = ->(req) { [200, encrypt_for(req[:presented], JSON.generate(PLAINTEXT)).except("tag")] }
    with_stub(strip) do |conn, _|
      error = assert_raises(Error) { conn.get(SECRETS_PATH) }
      assert_equal Error::DECRYPTION_FAILED, error.code
    end
  end

  def test_the_global_and_provider_lists_are_held_to_the_same_rule
    with_stub(->(_req) { [200, { "secrets" => [] }] }) do |conn, _|
      ["/api/v1/projects/p/secrets", "/api/v1/projects/p/environments/e/providers/v/secrets"].each do |path|
        error = assert_raises(Error, path) { conn.get(path) }
        assert_equal Error::PLAINTEXT_RESPONSE, error.code
      end
    end
  end

  def test_the_error_is_a_decryption_error
    assert_operator Error, :<, BellaBaxter::DecryptionError
    assert_operator Error, :<, BellaBaxter::Error
  end

  # ── What the rule must NOT touch ─────────────────────────────────────────────

  def test_plain_json_where_no_envelope_is_required_passes_through
    with_stub(->(_req) { [200, { "version" => 7 }] }) do |conn, _|
      assert_equal 7, JSON.parse(conn.get("#{SECRETS_PATH}/version").body)["version"]
      assert_equal 7, JSON.parse(conn.post(SECRETS_PATH, "{}").body)["version"]
    end
  end

  def test_a_non_2xx_answer_is_not_turned_into_this_error
    with_stub(->(_req) { [403, { "type" => "zke-device-not-registered" }] }) do |conn, _|
      resp = conn.get(SECRETS_PATH)
      assert_equal 403, resp.status
      assert_equal "zke-device-not-registered", JSON.parse(resp.body)["type"]
    end
  end

  def test_the_envelope_required_reads_are_exactly_the_contracts_table
    required = %w[
      /api/v1/projects/p/secrets
      /api/v1/projects/p/environments/e/secrets
      /api/v1/projects/p/environments/e/secrets/export
      /api/v1/projects/p/environments/e/providers/v/secrets
      /api/v1/projects/p/environments/e/providers/v/secrets/export
      /api/v1/projects/p/environments/e/providers/v/secrets/DB_URL
      /api/v1/projects/p/environments/e/providers/v/secrets/DB_URL/versions/3
      /bella/api/v1/projects/p/environments/e/secrets
    ]
    not_required = %w[
      /api/v1/projects/p/environments/e/secrets/version
      /api/v1/projects/p/environments/e/secrets/manifest
      /api/v1/projects/p/environments/e/secrets/certificates
      /api/v1/projects/p/environments/e/providers/v/secrets/hash
      /api/v1/projects/p/environments/e/providers/v/secrets/DB_URL/metadata
      /api/v1/projects/p/environments/e/providers/v/secrets/DB_URL/versions
      /api/v1/projects/p/environments/e/providers/v/secrets/DB_URL/versions/latest
      /api/v1/projects/p/environments/e/providers/v/secrets/DB_URL/rotation-policy
      /api/v1/projects/p/environments/e/providers/v/secrets/import/preview
      /api/v1/projects/p
      /api/v1/tenants/me/zke
    ]
    m = BellaBaxter::E2EEFaradayMiddleware
    required.each { |p| assert m.requires_envelope?(:get, p), "GET #{p} should require an envelope" }
    not_required.each { |p| refute m.requires_envelope?(:get, p), "GET #{p} should not require one" }
    %i[post put patch delete].each do |verb|
      refute m.requires_envelope?(verb, SECRETS_PATH), "#{verb.upcase} never requires an envelope"
    end
  end

  private

  # EciesAlgorithm.Encrypt, the server side of the E2EE contract (as contract-tests/stub/server.mjs).
  def encrypt_for(client_spki_b64, plaintext)
    client_key = OpenSSL::PKey.read(Base64.strict_decode64(client_spki_b64))
    ephemeral  = OpenSSL::PKey::EC.generate("prime256v1")
    shared     = ephemeral.derive(client_key)
    aes_key    = OpenSSL::KDF.hkdf(shared, salt: "\x00" * 32, info: "bella-e2ee-v1", length: 32, hash: "SHA256")
    cipher     = OpenSSL::Cipher.new("aes-256-gcm").encrypt
    cipher.key = aes_key
    nonce      = cipher.random_iv
    cipher.auth_data = ""
    ciphertext = cipher.update(plaintext) + cipher.final
    {
      "encrypted"       => true,
      "algorithm"       => "ECDH-P256-HKDF-SHA256-AES256GCM",
      "serverPublicKey" => Base64.strict_encode64(ephemeral.public_to_der),
      "nonce"           => Base64.strict_encode64(nonce),
      "tag"             => Base64.strict_encode64(cipher.auth_tag),
      "ciphertext"      => Base64.strict_encode64(ciphertext)
    }
  end

  # A one-connection-at-a-time HTTP/1.1 stub. +respond+ gets {method:, path:, presented:} and returns
  # [status, body]; a String body is sent as-is (text/plain), anything else as JSON.
  def with_stub(respond)
    server = TCPServer.new("127.0.0.1", 0)
    requests = []
    thread = Thread.new do
      loop do
        sock = server.accept
        line = sock.gets or next sock.close
        method, path, = line.split(" ")
        headers = {}
        while (h = sock.gets) && h != "\r\n"
          k, v = h.split(":", 2)
          headers[k.strip.downcase] = v.to_s.strip
        end
        sock.read(headers["content-length"].to_i) if headers["content-length"]
        req = { method: method, path: path, presented: headers["x-e2e-public-key"] }
        requests << req
        status, body = respond.call(req)
        text, type = body.is_a?(String) ? [body, "text/plain"] : [JSON.generate(body), "application/json"]
        sock.write("HTTP/1.1 #{status} X\r\nContent-Type: #{type}\r\n" \
                   "Content-Length: #{text.bytesize}\r\nConnection: close\r\n\r\n#{text}")
        sock.close
      end
    end
    conn = Faraday.new(url: "http://127.0.0.1:#{server.addr[1]}") do |f|
      f.use BellaBaxter::E2EEFaradayMiddleware
      f.adapter :net_http
    end
    yield conn, requests
  ensure
    thread&.kill
    server&.close
  end
end
