#!/usr/bin/env bash
# Issue #991 — prove the gem that would be published loads and decodes a response.
#
#   scripts/verify_gem.sh              # uses the generated client already in lib/bella_baxter/generated
#   scripts/verify_gem.sh --generate   # first regenerates it from the committed kiota-lock.json
#
# Builds the gem exactly as the publish workflow does (`gem build bella_baxter.gemspec`), installs it
# into a throwaway GEM_HOME, and runs test/*_test.rb against that INSTALLED copy — never against lib/
# in this tree. A check that loaded lib/ directly would pass even if the gemspec dropped the generated
# client from the package.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
GENERATED="$ROOT/lib/bella_baxter/generated"

if [ "${1:-}" = "--generate" ]; then
  command -v kiota >/dev/null 2>&1 || { echo "kiota is required for --generate (dotnet tool install --global Microsoft.OpenApi.Kiota --version 1.30.0)" >&2; exit 1; }
  # `kiota update` does not clean its output, so a stale file from an earlier generation (e.g. a
  # different namespace) would survive and be packaged. Keep only the committed lock.
  find "$GENERATED" -mindepth 1 -maxdepth 1 ! -name kiota-lock.json -exec rm -rf {} +
  kiota update --output "$GENERATED" --log-level Error
  ruby "$ROOT/scripts/fix_generated_primitives.rb" "$GENERATED"
fi

if [ ! -f "$GENERATED/bella_client.rb" ]; then
  echo "no generated client in $GENERATED — run: scripts/verify_gem.sh --generate" >&2
  exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "ruby: $(ruby -e 'print RUBY_DESCRIPTION')"
(cd "$ROOT" && gem build bella_baxter.gemspec --output "$WORK/bella_baxter.gem" >/dev/null)
echo "built: $(ruby -e 'require "rubygems/package"; s = Gem::Package.new(ARGV[0]).spec; print "#{s.full_name} (#{s.files.count { |f| f.include?("/generated/") }} generated files)"' "$WORK/bella_baxter.gem")"

export GEM_HOME="$WORK/gems" GEM_PATH="$WORK/gems"
gem install --no-document --quiet "$WORK/bella_baxter.gem" minitest >/dev/null
echo "installed: $(gem list '^(bella_baxter|microsoft_kiota|faraday)' | tr '\n' ' ')"

cd "$WORK"   # nothing from this tree on the load path
status=0
for t in "$ROOT"/test/*_test.rb; do
  ruby "$t" || status=1
done
exit "$status"
