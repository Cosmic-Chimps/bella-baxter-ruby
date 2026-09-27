# frozen_string_literal: true

# The device key rules every SDK shares (the same hold in JS, Java, .NET, Swift, Dart, Go, Python, PHP):
#   * the key must be P-256. The platform's ECIES is P-256 only; another curve used to load here and
#     then fail on the server with an unclear error;
#   * a BLANK BELLA_BAXTER_PRIVATE_KEY (empty or whitespace) means "no device key". `ENV[...] = ""` is
#     truthy in Ruby, so it used to raise instead.
#
# Loads only the E2EE module, so it runs without the generated client:
#   ruby -Ilib test/device_key_rules_test.rb
# Keys are generated per test, so no key material is committed.

require "minitest/autorun"
require "openssl"
require_relative "../lib/bella_baxter/e2ee"

class DeviceKeyRulesTest < Minitest::Test
  def setup
    @saved = ENV["BELLA_BAXTER_PRIVATE_KEY"]
  end

  def teardown
    ENV["BELLA_BAXTER_PRIVATE_KEY"] = @saved
  end

  def test_a_p256_key_loads
    pair = BellaBaxter::E2EE::KeyPair.from_pem(OpenSSL::PKey::EC.generate("prime256v1").private_to_pem)
    refute_empty pair.public_key_b64
  end

  def test_a_p384_key_is_refused_naming_the_curve
    error = assert_raises(ArgumentError) do
      BellaBaxter::E2EE::KeyPair.from_pem(OpenSSL::PKey::EC.generate("secp384r1").private_to_pem)
    end
    assert_match(/P-256.*secp384r1/, error.message)
  end

  def test_a_blank_variable_means_no_device_key
    ["", "   ", "\n\t "].each do |blank|
      ENV["BELLA_BAXTER_PRIVATE_KEY"] = blank
      assert_nil BellaBaxter::E2EE.resolve_device_key(nil), "variable #{blank.inspect}"
      assert_nil BellaBaxter::E2EE.resolve_device_key(blank), "explicit #{blank.inspect}"
    end
  end

  def test_an_explicit_key_wins_over_the_variable
    ENV["BELLA_BAXTER_PRIVATE_KEY"] = "from-env"
    assert_equal "explicit", BellaBaxter::E2EE.resolve_device_key("explicit")
    assert_equal "from-env", BellaBaxter::E2EE.resolve_device_key("  ")
    assert_equal "from-env", BellaBaxter::E2EE.resolve_device_key(nil)
  end

  def test_no_key_anywhere_means_nil
    ENV.delete("BELLA_BAXTER_PRIVATE_KEY")
    assert_nil BellaBaxter::E2EE.resolve_device_key(nil)
  end
end
