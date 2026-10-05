# frozen_string_literal: true

# Issue #1162 — the README documented options the gem does not have: `project:`/`environment:` on
# Client.new, `c.project`/`c.environment`/`c.enable_e2ee` in `configure`, and create/update/delete_secret
# methods. Each one is an ArgumentError or NoMethodError the moment someone copies it.
#
# This test reads every ```ruby block in README.md and samples/**/README.md and checks, against the REAL
# classes loaded from the gem (never a hand-copied list):
#   - every block parses;
#   - every keyword passed to BellaBaxter::Client.new is a Client#initialize keyword or a Configuration member;
#   - every `c.x = …` inside `BellaBaxter.configure do |c|` is a Configuration setter;
#   - every method called on `client` / `BellaBaxter.client` is a public Client method, and every method
#     called on `BellaBaxter` is a module method, each with keywords that method accepts.
# Run through scripts/verify_gem.sh (against the installed gem), or: ruby -Ilib test/readme_test.rb

require "minitest/autorun"
require "prism"

require "bella_baxter"

class ReadmeTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  DOCS = [File.join(ROOT, "README.md"), *Dir[File.join(ROOT, "samples", "**", "README.md")]].freeze

  # A receiver that is the SDK client: `client` (a local, or a bare name in a block that never assigns it,
  # which Prism reads as a method call) or `BellaBaxter.client`.
  def client_receiver?(node)
    case node
    when Prism::LocalVariableReadNode then node.name == :client
    when Prism::CallNode
      (node.name == :client && node.receiver.nil? && node.arguments.nil?) || bella_call?(node, :client)
    else false
    end
  end

  def bella_constant?(node)
    node.is_a?(Prism::ConstantReadNode) && node.name == :BellaBaxter
  end

  def bella_call?(node, name)
    node.is_a?(Prism::CallNode) && node.name == name && bella_constant?(node.receiver)
  end

  def client_constant?(node)
    node.is_a?(Prism::ConstantPathNode) && node.name == :Client && bella_constant?(node.parent)
  end

  def keywords(call)
    (call.arguments&.arguments || []).grep(Prism::KeywordHashNode).flat_map(&:elements)
                                     .map { |a| a.key.respond_to?(:unescaped) ? a.key.unescaped.to_sym : nil }.compact
  end

  # Keyword names a method accepts, or nil when it takes **opts (anything goes at this layer).
  def accepted_keywords(method)
    params = method.parameters
    return nil if params.any? { |type, _| type == :keyrest }

    params.select { |type, _| %i[key keyreq].include?(type) }.map(&:last)
  end

  def blocks
    DOCS.flat_map do |doc|
      File.read(doc).scan(/^```ruby\n(.*?)^```/m).flatten.each_with_index.map do |code, i|
        ["#{File.basename(File.dirname(doc))}/#{File.basename(doc)} ruby block ##{i + 1}", code]
      end
    end
  end

  def test_the_readmes_have_ruby_samples
    refute_empty blocks, "no ```ruby blocks found — the extraction itself is broken"
  end

  def test_every_ruby_block_parses
    blocks.each do |where, code|
      result = Prism.parse(code)
      assert result.success?, "#{where} does not parse: #{result.errors.map(&:message).join('; ')}"
    end
  end

  def test_every_documented_call_exists_with_the_keywords_it_is_given
    client_init_keywords = BellaBaxter::Client.instance_method(:initialize).parameters
                                              .select { |t, _| %i[key keyreq].include?(t) }.map(&:last)
    config_members = BellaBaxter::Configuration.members
    problems = []

    blocks.each do |where, code|
      tree = Prism.parse(code).value
      configure_params = []
      walk(tree) do |node|
        next unless node.is_a?(Prism::CallNode)

        if bella_call?(node, :configure) && node.block&.parameters
          configure_params.concat(node.block.parameters.parameters.requireds.map(&:name))
        end
      end

      walk(tree) do |node|
        next unless node.is_a?(Prism::CallNode)

        if node.name == :new && client_constant?(node.receiver)
          (keywords(node) - client_init_keywords - config_members).each do |kw|
            problems << "#{where}: BellaBaxter::Client.new(#{kw}:) — not a Client or Configuration option " \
                        "(accepted: #{(client_init_keywords + config_members).join(', ')})"
          end
        elsif node.receiver.is_a?(Prism::LocalVariableReadNode) && configure_params.include?(node.receiver.name)
          setter = node.name.to_s
          unless setter.end_with?("=") && BellaBaxter::Configuration.method_defined?(setter)
            problems << "#{where}: configure block sets `#{setter.chomp('=')}`, which Configuration does not have " \
                        "(members: #{config_members.join(', ')})"
          end
        elsif client_receiver?(node.receiver)
          check_method(problems, where, "client.#{node.name}", BellaBaxter::Client, node)
        elsif bella_constant?(node.receiver) && node.name != :client
          check_method(problems, where, "BellaBaxter.#{node.name}", BellaBaxter.singleton_class, node)
        end
      end
    end

    assert_empty problems, "README samples that would not run:\n  #{problems.join("\n  ")}"
  end

  # The configure path the README documents must not raise (it passed project:/environment: to
  # Configuration.new and raised ArgumentError on the first call).
  def test_configure_runs
    previous = BellaBaxter.configuration
    BellaBaxter.configuration = nil
    BellaBaxter.configure { |c| c.timeout = 5 }
    assert_equal 5, BellaBaxter.configuration.timeout
  ensure
    BellaBaxter.configuration = previous
  end

  private

  def check_method(problems, where, label, owner, call)
    unless owner.public_method_defined?(call.name)
      problems << "#{where}: #{label} — no such public method"
      return
    end
    allowed = accepted_keywords(owner.instance_method(call.name))
    return if allowed.nil?

    (keywords(call) - allowed).each do |kw|
      problems << "#{where}: #{label}(#{kw}:) — not a keyword of that method (accepted: #{allowed.join(', ')})"
    end
  end

  def walk(node, &block)
    return unless node.is_a?(Prism::Node)

    yield node
    node.compact_child_nodes.each { |child| walk(child, &block) }
  end
end
