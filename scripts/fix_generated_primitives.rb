# frozen_string_literal: true

# Issue #991 — make the Kiota-generated Ruby client loadable past its number fields.
#
#   ruby scripts/fix_generated_primitives.rb [lib/bella_baxter/generated]
#
# Run it after EVERY `kiota generate` / `kiota update` of the Ruby client: apps/sdk/generate.sh, the
# gem's own publish workflow (.github/workflows/publish.yml) and scripts/verify_gem.sh all do.
#
# Why it exists. Kiota 1.30.0's Ruby generator has no mapping for the `int64` and `double` formats.
# Every other format it knows becomes a primitive read (`int32` -> `n.get_number_value()`); these two
# fall through to the object path and name a class that does not exist:
#
#   "version" => lambda {|n| @version = n.get_object_value(lambda {|pn| Int64.create_from_discriminator_value(pn) }) },
#   writer.write_object_value("version", @version)
#
# so decoding any response carrying one raises NameError, and serializing one raises NoMethodError
# (an Integer has no #serialize). There is no Kiota option or type mapping that changes this, and the
# schema-side alternative (int64 -> int32) would narrow a contract eleven other SDKs publish as a
# 64-bit integer. So the generated code is corrected here, to the readers and writers the Kiota JSON
# runtime actually provides: get/write_number_value (Integer) and get/write_float_value (Float).
#
# The step FAILS rather than quietly doing nothing:
#   - if it rewrites nothing at all (the pattern changed, e.g. after a Kiota upgrade — re-read the
#     generated code; if Kiota fixed the mapping upstream, delete this script and its callers);
#   - if a deserializer it rewrote has no matching serializer line, or more than one;
#   - if, afterwards, any generated factory still names a class the generated tree does not define
#     (Int64/Double in a shape this script does not know, or a new unmapped format).

require "set"

GENERATED_DIR = File.expand_path(ARGV[0] || File.join(__dir__, "..", "lib", "bella_baxter", "generated"))

# Kiota's name for the format => [reader, writer, Ruby class for primitive collections]
PRIMITIVES = {
  "Int64" => %w[get_number_value write_number_value Integer],
  "Double" => %w[get_float_value write_float_value Float]
}.freeze

TYPES = PRIMITIVES.keys.join("|")

DESERIALIZER = /
  "(?<key>[^"]+)"\s=>\slambda\s\{\|n\|\s@(?<ivar>\w+)\s=\s
  n\.get_object_value\(lambda\s\{\|pn\|\s(?<type>#{TYPES})\.create_from_discriminator_value\(pn\)\s\}\)\s\},
/x

COLLECTION = /get_collection_of_primitive_values\((?<type>#{TYPES})\)/

def abort!(message)
  warn "fix_generated_primitives: #{message}"
  exit 1
end

abort!("#{GENERATED_DIR} does not exist — generate the client first") unless File.directory?(GENERATED_DIR)

files = Dir.glob(File.join(GENERATED_DIR, "**", "*.rb")).sort
abort!("no generated Ruby files under #{GENERATED_DIR}") if files.empty?

rewritten = Hash.new(0)

files.each do |path|
  source = File.read(path)
  updated = source.dup

  source.scan(DESERIALIZER) do
    m = Regexp.last_match
    key, ivar, type = m[:key], m[:ivar], m[:type]
    reader, writer, = PRIMITIVES.fetch(type)

    updated = updated.sub(m[0], %("#{key}" => lambda {|n| @#{ivar} = n.#{reader}() },))

    serializer = %(writer.write_object_value("#{key}", @#{ivar}))
    count = updated.scan(serializer).length
    abort!("#{path}: #{key} (#{type}) has #{count} serializer lines `#{serializer}`, expected exactly 1") unless count == 1

    updated = updated.sub(serializer, %(writer.#{writer}("#{key}", @#{ivar})))
    rewritten[type] += 1
  end

  updated = updated.gsub(COLLECTION) do
    rewritten["#{Regexp.last_match[:type]}[]"] += 1
    "get_collection_of_primitive_values(#{PRIMITIVES.fetch(Regexp.last_match[:type])[2]})"
  end

  File.write(path, updated) unless updated == source
end

abort!(<<~MSG) if rewritten.empty?
  rewrote nothing under #{GENERATED_DIR}. Either this output was already fixed (the script runs ONCE
  per generation — regenerate first), or Kiota no longer emits `Int64/Double.create_from_discriminator_value`
  in the shape this script expects. Read the generated models: if int64/double fields now use a
  primitive reader, Kiota fixed the mapping and this script (and its callers) can be deleted; if they
  use a new shape, extend the patterns here. Either way, do not publish until it is resolved.
MSG

# Every class a generated factory names must exist. A bare name (no `::`) is resolved against the
# classes the generated tree defines; anything else — a leftover Int64/Double, a new unmapped format
# — would be a NameError at the first response that carries it.
defined_classes = files.flat_map { |f| File.read(f).scan(/^\s*class (\w+)/).flatten }.to_set
unknown = files.flat_map do |f|
  File.read(f).each_line.with_index(1).flat_map do |line, lineno|
    next [] if line.lstrip.start_with?("#")

    names = line.scan(/lambda \{\|pn\| ([A-Z]\w*)\.create_from_discriminator_value/).flatten
    names += line.scan(/get_collection_of_primitive_values\(([A-Z]\w*)\)/).flatten
    names.reject { |n| defined_classes.include?(n) || %w[String Integer Float Date DateTime Time].include?(n) }
         .map { |n| "#{f.delete_prefix("#{GENERATED_DIR}/")}:#{lineno}: #{n}" }
  end
end
unless unknown.empty?
  abort!("generated code still names classes that do not exist:\n  #{unknown.first(20).join("\n  ")}" \
         "#{unknown.size > 20 ? "\n  … and #{unknown.size - 20} more" : ''}")
end

puts "fix_generated_primitives: rewrote #{rewritten.map { |t, n| "#{n} #{t}" }.join(', ')} under #{GENERATED_DIR}"
