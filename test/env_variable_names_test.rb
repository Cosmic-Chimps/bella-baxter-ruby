# frozen_string_literal: true

# Issue #1483 — the Railtie looked only at BELLA_API_KEY, a deprecated alias. The documented name,
# BELLA_BAXTER_API_KEY (public-docs/sdks/ruby.md), loaded nothing and logged nothing, so a Rails app
# configured exactly as documented booted without its secrets and without a word about why.
#
# Run through scripts/verify_gem.sh (against the installed gem), or: ruby -Ilib test/env_variable_names_test.rb

require "minitest/autorun"
require "logger"
require "stringio"

require "bella_baxter"

class EnvVariableNamesTest < Minitest::Test
  API_KEY = "bax-0123456789abcdef0123456789abcdef-#{'ab' * 32}"
  OTHER_API_KEY = "bax-fedcba9876543210fedcba9876543210-#{'cd' * 32}"
  VARIABLES = %w[
    BELLA_BAXTER_API_KEY BELLA_API_KEY BELLA_BAXTER_URL BELLA_API_URL BELLA_BAXTER_ACCESS_TOKEN
    BELLA_BAXTER_PRIVATE_KEY
  ].freeze

  def setup
    @saved_env = VARIABLES.to_h { |v| [v, ENV.fetch(v, nil)] }
    VARIABLES.each { |v| ENV.delete(v) }

    @log = StringIO.new
    @saved_logger = BellaBaxter.instance_variable_get(:@logger)
    BellaBaxter.instance_variable_set(:@logger, Logger.new(@log))

    # Stand in for the network: record the configuration the Railtie builds a client with.
    @configs = []
    configs = @configs
    @original_new = BellaBaxter::Client.method(:new)
    fake = Class.new do
      define_method(:load_into_env!) { 3 }
      define_method(:key_context) { { "projectSlug" => "p", "environmentSlug" => "e" } }
    end
    BellaBaxter::Client.define_singleton_method(:new) do |private_key: nil, **opts|
      _ = private_key
      configs << (opts[:config] || BellaBaxter::Configuration.new(**opts))
      fake.new
    end
  end

  def teardown
    original = @original_new
    BellaBaxter::Client.define_singleton_method(:new) { |*args, **kw, &blk| original.call(*args, **kw, &blk) }
    BellaBaxter.instance_variable_set(:@logger, @saved_logger)
    @saved_env.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  def warnings
    @log.string.lines.grep(/WARN/)
  end

  def test_the_documented_api_key_name_loads_the_secrets
    ENV["BELLA_BAXTER_API_KEY"] = API_KEY
    ENV["BELLA_BAXTER_URL"] = "https://baxter.example.com"

    BellaBaxter.auto_load_from_env!

    assert_equal 1, @configs.size, "BELLA_BAXTER_API_KEY alone must be enough to load secrets"
    assert_equal API_KEY, @configs.first.api_key
    assert_equal "https://baxter.example.com", @configs.first.baxter_url
    assert_empty warnings
  end

  def test_the_deprecated_alias_still_loads_the_secrets
    ENV["BELLA_API_KEY"] = API_KEY
    ENV["BELLA_API_URL"] = "https://alias.example.com"

    BellaBaxter.auto_load_from_env!

    assert_equal 1, @configs.size
    assert_equal API_KEY, @configs.first.api_key
    assert_equal "https://alias.example.com", @configs.first.baxter_url
  end

  def test_the_canonical_names_win_over_the_aliases
    ENV["BELLA_BAXTER_API_KEY"] = API_KEY
    ENV["BELLA_API_KEY"] = OTHER_API_KEY
    ENV["BELLA_BAXTER_URL"] = "https://canonical.example.com"
    ENV["BELLA_API_URL"] = "https://alias.example.com"

    BellaBaxter.auto_load_from_env!

    assert_equal API_KEY, @configs.first.api_key
    assert_equal "https://canonical.example.com", @configs.first.baxter_url
  end

  def test_no_credential_logs_one_warning_naming_the_variables_it_looked_for
    BellaBaxter.auto_load_from_env!

    assert_empty @configs
    assert_equal 1, warnings.size
    assert_includes warnings.first, "BELLA_BAXTER_API_KEY"
    assert_includes warnings.first, "BELLA_API_KEY"
  end

  def test_a_bearer_token_alone_is_explained_not_silently_ignored
    # `bella sdk run` in JWT mode injects BELLA_BAXTER_ACCESS_TOKEN. This client signs with an API key
    # (HMAC) and has no bearer-token path, so the honest outcome is a warning that says so.
    ENV["BELLA_BAXTER_ACCESS_TOKEN"] = "eyJ-not-a-real-token"
    ENV["BELLA_BAXTER_URL"] = "https://baxter.example.com"

    BellaBaxter.auto_load_from_env!

    assert_empty @configs
    assert_equal 1, warnings.size
    assert_includes warnings.first, "BELLA_BAXTER_ACCESS_TOKEN"
    assert_includes warnings.first, "API key"
  end

  def test_a_warning_never_carries_a_value
    ENV["BELLA_BAXTER_ACCESS_TOKEN"] = "eyJ-not-a-real-token"

    BellaBaxter.auto_load_from_env!

    refute_includes @log.string, "eyJ-not-a-real-token"
  end

  def test_a_missing_address_is_one_warning_naming_both_url_variables
    ENV["BELLA_BAXTER_API_KEY"] = API_KEY

    BellaBaxter.auto_load_from_env!

    assert_empty @configs
    assert_equal 1, warnings.size
    assert_includes warnings.first, "BELLA_BAXTER_URL"
    assert_includes warnings.first, "BELLA_API_URL"
    refute_includes @log.string, API_KEY
  end

  def test_configure_and_from_env_read_the_documented_names_too
    ENV["BELLA_BAXTER_API_KEY"] = API_KEY
    ENV["BELLA_BAXTER_URL"] = "https://baxter.example.com"
    BellaBaxter.configuration = nil

    BellaBaxter.configure { |c| c.timeout = 5 }

    assert_equal API_KEY, BellaBaxter.configuration.api_key
    assert_equal "https://baxter.example.com", BellaBaxter.configuration.baxter_url
  ensure
    BellaBaxter.configuration = nil
  end

  def test_from_env_reads_the_documented_names_and_names_them_when_missing
    ENV["BELLA_BAXTER_API_KEY"] = API_KEY
    ENV["BELLA_BAXTER_URL"] = "https://baxter.example.com"
    BellaBaxter::Client.from_env
    assert_equal API_KEY, @configs.first.api_key

    ENV.delete("BELLA_BAXTER_API_KEY")
    error = assert_raises(KeyError) { BellaBaxter::Client.from_env }
    assert_includes error.message, "BELLA_BAXTER_API_KEY"
  end
end
