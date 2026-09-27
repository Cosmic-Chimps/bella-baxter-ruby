# frozen_string_literal: true

# Issue #991 — the published gem could not be loaded, and nothing noticed, because no test ever
# required it. Run through scripts/verify_gem.sh, which builds the gem, installs it into a throwaway
# GEM_HOME and runs this file against the INSTALLED copy — so what is proven is the artifact that
# `gem push` would publish, not the source tree beside it.
#
#   scripts/verify_gem.sh
#
# Two defects shipped together and each is pinned here:
#   1. the Kiota namespace `bella_baxter/generated` became `module Bella_baxter/generated` — a
#      SyntaxError on `require`;
#   2. int64/double fields named `Int64`/`Double`, classes that do not exist — a NameError at the first
#      response carrying one, which includes every `all_secrets` call (`version` is int64).

require "minitest/autorun"
require "json"
require "socket"

require "bella_baxter"

class GemLoadsTest < Minitest::Test
  PROJECT = "contract-project"
  ENVIRONMENT = "production"

  # A realistic GET …/secrets body. `version` is the int64 that raised NameError, and is deliberately
  # larger than 2**31 so a 32-bit read could not pass for a correct one.
  ALL_SECRETS_BODY = {
    "environmentSlug" => ENVIRONMENT,
    "environmentName" => "Production",
    "secrets" => {
      "DATABASE_URL" => "postgres://app:s3cret@db.internal:5432/app",
      "PORT" => "8080",
      "APP_CONFIG" => "{\"feature\":true}"
    },
    "version" => 1_790_000_000_123,
    "lastModified" => "2026-09-26T10:00:00Z"
  }.freeze

  API_KEY = "bax-0123456789abcdef0123456789abcdef-#{'ab' * 32}"

  def generated_dir
    entry = $LOAD_PATH.resolve_feature_path("bella_baxter")
    refute_nil entry, "bella_baxter is not on the load path"
    File.join(File.dirname(entry.last), "bella_baxter", "generated")
  end

  def parse(model, body)
    node = MicrosoftKiotaSerializationJson::JsonParseNodeFactory.new
                                                                .get_parse_node("application/json", JSON.generate(body))
    node.get_object_value(model.method(:create_from_discriminator_value))
  end

  def serialize(model_instance)
    writer = MicrosoftKiotaSerializationJson::JsonSerializationWriter.new
    writer.write_object_value(nil, model_instance)
    JSON.parse(writer.get_serialized_content)
  end

  # ── 1. It loads ─────────────────────────────────────────────────────────────

  def test_the_generated_client_is_loaded_not_silently_skipped
    # client.rb rescues LoadError around the generated require, so a gem without its generated client
    # still `require`s cleanly and fails later with an uninitialized constant. Assert the constant.
    assert defined?(BellaBaxterGenerated::BellaClient), "BellaBaxterGenerated::BellaClient is not defined"
    assert File.file?(File.join(generated_dir, "bella_client.rb")), "the gem carries no generated client"
  end

  def test_every_generated_file_parses_and_loads
    files = Dir.glob(File.join(generated_dir, "**", "*.rb"))
    assert_operator files.size, :>, 100, "expected the full generated tree, found #{files.size} files"
    files.each { |f| require f }
  end

  # Every factory a generated model names must resolve, in the lexical scope Ruby will look it up in.
  # This is the guard for "a new format maps to a class that does not exist" — the Int64 defect in
  # general form — without needing a response that happens to carry the field.
  def test_every_factory_a_model_names_exists
    test_every_generated_file_parses_and_loads
    missing = []
    checked = 0
    Dir.glob(File.join(generated_dir, "models", "*.rb")).each do |f|
      source = File.read(f)
      klass_name = source[/^\s*class (\w+)/, 1] or next
      # innermost first, as Ruby's lexical constant lookup does for `module BellaBaxterGenerated;
      # module Models; class <klass_name>`
      scopes = [BellaBaxterGenerated::Models.const_get(klass_name), BellaBaxterGenerated::Models, BellaBaxterGenerated, Object]
      source.scan(/lambda \{\|pn\| ([A-Z][\w:]*)\.create_from_discriminator_value/).flatten.uniq.each do |ref|
        checked += 1
        target = scopes.lazy.map { |scope| resolve(scope, ref) }.find(&:itself)
        missing << "#{File.basename(f)}: #{ref}" unless target.respond_to?(:create_from_discriminator_value)
      end
    end
    assert_operator checked, :>, 100, "expected to check the model factories, checked #{checked}"
    assert_empty missing, "generated models name factories that do not exist:\n  #{missing.join("\n  ")}"
  end

  # ── 2. A client can be constructed ──────────────────────────────────────────

  def test_a_client_can_be_constructed
    client = BellaBaxter::Client.new(baxter_url: "https://bella.example.test", api_key: API_KEY)
    assert_kind_of BellaBaxterGenerated::BellaClient, client.client
  end

  # ── 3. The int64/double fields decode through the real Kiota JSON parse node ─

  def test_all_environment_secrets_response_decodes_with_its_int64_version
    r = parse(BellaBaxterGenerated::Models::AllEnvironmentSecretsResponse, ALL_SECRETS_BODY)
    assert_equal ENVIRONMENT, r.environment_slug
    assert_equal "Production", r.environment_name
    assert_equal 1_790_000_000_123, r.version
    assert_kind_of Integer, r.version
    assert_equal ALL_SECRETS_BODY["secrets"], r.secrets.additional_data
    assert_equal DateTime.parse("2026-09-26T10:00:00Z"), r.last_modified
  end

  def test_all_environment_secrets_response_serializes_its_int64_version
    r = parse(BellaBaxterGenerated::Models::AllEnvironmentSecretsResponse, ALL_SECRETS_BODY)
    # write_object_value on an Integer raised NoMethodError (#serialize) before the fix.
    assert_equal 1_790_000_000_123, serialize(r)["version"]
  end

  # The two examples #991 names.
  def test_paged_int64_counts_decode
    page = parse(BellaBaxterGenerated::Models::PageProjectResponse,
                 { "totalElements" => 4_000_000_000, "totalPages" => 2, "content" => [] })
    assert_equal 4_000_000_000, page.total_elements

    log = parse(BellaBaxterGenerated::Models::CertRotationLogPage,
                { "totalCount" => 3_000_000_001, "page" => 1, "size" => 50, "items" => [] })
    assert_equal 3_000_000_001, log.total_count
  end

  # The `double` format had the same defect (`Double.create_from_discriminator_value`).
  def test_double_fields_decode_and_serialize
    usage = parse(BellaBaxterGenerated::Models::TenantUsageResponse,
                  { "overageRatePerRequest" => 0.0005, "estimatedOverageCost" => 12 })
    assert_in_delta 0.0005, usage.overage_rate_per_request
    # JSON writes a whole number without a fraction; a double field must still read it.
    assert_in_delta 12.0, usage.estimated_overage_cost
    assert_in_delta 0.0005, serialize(usage)["overageRatePerRequest"]
  end

  # ── 4. all_secrets works end to end, over HTTP, through the Kiota request adapter ─

  def test_all_secrets_decodes_a_response_from_a_server
    with_stub_server do |url, requests|
      client = BellaBaxter::Client.new(baxter_url: url, api_key: API_KEY)
      resp = client.all_secrets

      assert_equal ENVIRONMENT, resp.environment_slug
      assert_equal "Production", resp.environment_name
      assert_equal 1_790_000_000_123, resp.version
      assert_equal ALL_SECRETS_BODY["secrets"], resp.secrets

      secrets_request = requests.find { |r| r[:path] == "/api/v1/projects/#{PROJECT}/environments/#{ENVIRONMENT}/secrets" }
      refute_nil secrets_request, "the client never asked for the secrets (requests: #{requests.map { |r| r[:path] }})"
      refute_nil secrets_request[:headers]["x-bella-signature"], "the secrets request was not HMAC-signed"
      refute_nil secrets_request[:headers]["x-e2e-public-key"], "the secrets request presented no E2E public key"
    end
  end

  private

  def resolve(scope, ref)
    ref.split("::").reduce(scope) { |mod, name| mod.const_get(name, mod.equal?(scope)) }
  rescue NameError
    nil
  end

  # A one-connection-at-a-time HTTP/1.1 server answering the two calls all_secrets makes. No Bella,
  # no network: the point is the client's decode path, not the platform.
  def with_stub_server
    server = TCPServer.new("127.0.0.1", 0)
    requests = []
    thread = Thread.new do
      loop do
        sock = server.accept
        request_line = sock.gets or next sock.close
        _method, path, = request_line.split(" ")
        headers = {}
        while (line = sock.gets) && line != "\r\n"
          k, v = line.split(":", 2)
          headers[k.strip.downcase] = v.to_s.strip
        end
        requests << { path: path, headers: headers }
        status, body =
          case path
          when "/api/v1/keys/me"
            [200, { "projectSlug" => PROJECT, "environmentSlug" => ENVIRONMENT }]
          when "/api/v1/projects/#{PROJECT}/environments/#{ENVIRONMENT}/secrets"
            [200, ALL_SECRETS_BODY]
          else
            [404, { "error" => "not stubbed: #{path}" }]
          end
        payload = JSON.generate(body)
        sock.write("HTTP/1.1 #{status} X\r\nContent-Type: application/json\r\n" \
                   "Content-Length: #{payload.bytesize}\r\nConnection: close\r\n\r\n#{payload}")
        sock.close
      end
    rescue IOError, Errno::EBADF
      # server closed
    end
    # The server answers each request before the client returns, so by the time the block inspects
    # `requests` every entry it cares about has been appended.
    yield "http://127.0.0.1:#{server.addr[1]}", requests
  ensure
    server&.close
    thread&.kill
  end
end
