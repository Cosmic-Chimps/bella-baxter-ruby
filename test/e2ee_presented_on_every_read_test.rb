# frozen_string_literal: true

# Issue #1162 — the key is presented on EVERY envelope-required read (apps/sdk/SDK_CONTRACT.md, "Rule: the
# key is presented on every envelope-required read"), not only on GETs ending in /secrets.
#
# Before the fix the middleware presented its key on getAllEnvironmentSecrets, listSecrets and
# listGlobalSecrets only, so getSecret, getSecretVersion and both exports reached the caller over TLS alone;
# and it re-wrapped every decrypted body that was not an AllEnvironmentSecretsResponse into a
# {"secrets": …} object, so a secret item or a ListGlobalSecretsResponse decrypted correctly and still
# arrived as the wrong thing. The stub answers each read with an envelope of that read's own plaintext.
#   ruby -Ilib test/e2ee_presented_on_every_read_test.rb

require_relative "e2ee_presented_key_requires_envelope_test"

class E2EEPresentedOnEveryReadTest < Minitest::Test
  K = E2EEPresentedKeyRequiresEnvelopeTest::SENTINEL_KEY
  V = E2EEPresentedKeyRequiresEnvelopeTest::SENTINEL_VALUE
  ITEM = {
    "key" => K, "value" => V, "description" => nil,
    "createdAt" => "2026-01-01T00:00:00Z", "updatedAt" => "2026-01-01T00:00:00Z", "type" => nil
  }.freeze
  ENV_PATH = "/api/v1/projects/p/environments/e"

  # [operationId, path incl. query, the plaintext the server encrypts for it]
  READS = [
    ["getAllEnvironmentSecrets", "#{ENV_PATH}/secrets",
     { "environmentSlug" => "e", "environmentName" => "e", "secrets" => { K => V }, "version" => 7,
       "lastModified" => "2026-10-04T00:00:00Z" }],
    ["exportEnvironmentSecrets", "#{ENV_PATH}/secrets/export?format=json", { K => V }],
    ["listSecrets", "#{ENV_PATH}/providers/v/secrets", [ITEM]],
    ["exportSecrets", "#{ENV_PATH}/providers/v/secrets/export?format=dotenv", { K => V }],
    ["getSecret", "#{ENV_PATH}/providers/v/secrets/#{K}", ITEM],
    ["getSecretVersion", "#{ENV_PATH}/providers/v/secrets/#{K}/versions/1", ITEM],
    ["listGlobalSecrets", "/api/v1/projects/p/secrets",
     { "projectRef" => "p", "projectSlug" => "p", "globalSecretProviderId" => nil,
       "secrets" => [ITEM.merge("tags" => {}, "ignoreInScan" => false)] }]
  ].freeze

  VALUE_LESS = [
    [:get, "#{ENV_PATH}/secrets/version"],
    [:get, "#{ENV_PATH}/providers/v/secrets/hash"],
    [:get, "#{ENV_PATH}/providers/v/secrets/#{K}/metadata"],
    [:get, "#{ENV_PATH}/providers/v/secrets/#{K}/versions"],
    [:post, "#{ENV_PATH}/providers/v/secrets"]
  ].freeze

  PLAIN_ANSWER = { "version" => 7 }.freeze

  READS.each do |operation, path, plaintext|
    define_method("test_#{operation}_presents_the_key_and_hands_the_plaintext_on_unchanged") do
      with_reads({ path.split("?").first => plaintext }) do |conn, requests|
        body = JSON.parse(conn.get(path).body)
        refute_nil requests.last[:presented], "#{operation}: the middleware did not present its key"
        assert_equal plaintext, body, "#{operation}: the decrypted body was reshaped"
      end
    end
  end

  def test_the_key_is_not_presented_where_nothing_is_encrypted
    with_reads({}) do |conn, requests|
      VALUE_LESS.each do |verb, path|
        body = verb == :get ? conn.get(path).body : conn.post(path, "{}").body
        assert_nil requests.last[:presented], "#{verb.upcase} #{path} presented the key"
        assert_equal PLAIN_ANSWER, JSON.parse(body)
      end
    end
  end

  def test_a_legacy_flat_dict_on_get_all_environment_secrets_is_still_wrapped
    with_reads({ "#{ENV_PATH}/secrets" => { K => V } }) do |conn, _|
      assert_equal({ K => V }, JSON.parse(conn.get("#{ENV_PATH}/secrets").body)["secrets"])
    end
  end

  private

  def helper
    @helper ||= E2EEPresentedKeyRequiresEnvelopeTest.new("helper")
  end

  # The envelope-required stub: the read's plaintext encrypted to the presented key, or PLAIN_ANSWER.
  def with_reads(plaintext_by_path, &block)
    respond = lambda do |req|
      plaintext = plaintext_by_path[req[:path].split("?").first]
      if plaintext && req[:presented]
        [200, helper.send(:encrypt_for, req[:presented], JSON.generate(plaintext))]
      else
        [200, PLAIN_ANSWER]
      end
    end
    helper.send(:with_stub, respond, &block)
  end
end
