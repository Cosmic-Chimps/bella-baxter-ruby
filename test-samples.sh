#!/usr/bin/env bash
# test-samples.sh — runs all Ruby SDK samples and validates expected secret values
# Usage: ./test-samples.sh <api-key>
set -euo pipefail

API_KEY="${1:-}"
if [[ -z "$API_KEY" ]]; then
  echo "Usage: $0 <api-key>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SAMPLES_DIR="$SCRIPT_DIR/samples"
DEMO_ENV="/Users/jjchiw/Documents/cosmic-chimps/a__cc/bella-baxter/demo.env"
BELLA_URL="http://localhost:5522"

RUBY=/opt/homebrew/opt/ruby@3.4/bin/ruby
GEM=/opt/homebrew/opt/ruby@3.4/bin/gem
BUNDLE=/opt/homebrew/opt/ruby@3.4/bin/bundle

# ── Expected values (from demo.env) ──────────────────────────────────────────
PORT_EXPECTED="$(grep '^PORT=' "$DEMO_ENV" | cut -d= -f2-)"
DATABASE_URL_EXPECTED="$(grep '^DATABASE_URL=' "$DEMO_ENV" | cut -d= -f2-)"
EXTERNAL_API_KEY_EXPECTED="$(grep '^EXTERNAL_API_KEY=' "$DEMO_ENV" | cut -d= -f2-)"
GLEAP_API_KEY_EXPECTED="$(grep '^GLEAP_API_KEY=' "$DEMO_ENV" | cut -d= -f2-)"
ENABLE_FEATURES_EXPECTED="$(grep '^ENABLE_FEATURES=' "$DEMO_ENV" | cut -d= -f2-)"
APP_ID_EXPECTED="$(grep '^APP_ID=' "$DEMO_ENV" | cut -d= -f2-)"
CONNSTRING_EXPECTED="$(grep '^ConnectionStrings__Postgres=' "$DEMO_ENV" | cut -d= -f2-)"
APP_CONFIG_EXPECTED="$(grep '^APP_CONFIG=' "$DEMO_ENV" | cut -d= -f2- | sed 's/^"//;s/"$//' | sed 's/\\"/"/g')"

# ── Result tracking ───────────────────────────────────────────────────────────
PASS=0
FAIL=0
declare -a RESULTS=()

pass() { PASS=$((PASS+1)); RESULTS+=("PASS: $1"); printf "  ✅ %s\n" "$1"; }
fail() { FAIL=$((FAIL+1)); RESULTS+=("FAIL: $1"); printf "  ❌ %s\n" "$1"; }

check_val() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label -- expected '$expected' got '$actual'"
  fi
}

check_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    pass "$label"
  else
    fail "$label -- expected to contain '$needle'"
  fi
}

# ── Authentication ────────────────────────────────────────────────────────────
echo ""
echo "─── Authentication ──────────────────────────────────────────────────"
if bella login --api-key "$API_KEY" --url "$BELLA_URL" 2>/dev/null; then
  pass "bella login --api-key"
else
  fail "bella login --api-key"
  echo "Cannot continue without authentication." >&2
  exit 1
fi

# ── Install dependencies ──────────────────────────────────────────────────────
echo ""
echo "─── Install dependencies ────────────────────────────────────────────"

for sample in 01-dotenv-file 03-standalone 04-rails 05-typed-secrets; do
  sdir="$SAMPLES_DIR/$sample"
  if [[ -f "$sdir/Gemfile" ]]; then
    if BUNDLE_GEMFILE="$sdir/Gemfile" "$BUNDLE" install --gemfile="$sdir/Gemfile" --quiet 2>/dev/null; then
      pass "bundle install $sample"
    else
      fail "bundle install $sample"
    fi
  fi
done

# ── 01-dotenv-file ────────────────────────────────────────────────────────────
echo ""
echo "─── 01-dotenv-file ──────────────────────────────────────────────────"
SAMPLE_01="$SAMPLES_DIR/01-dotenv-file"
DOT_ENV_FILE="$SAMPLE_01/.env"
rm -f "$DOT_ENV_FILE"

if bella secrets get --output "$DOT_ENV_FILE" 2>/dev/null; then
  pass "bella secrets get -o .env"
elif bella secrets get -o "$DOT_ENV_FILE" 2>/dev/null; then
  pass "bella secrets get -o .env"
else
  fail "bella secrets get -o .env"
fi

if [[ -f "$DOT_ENV_FILE" ]]; then
  _port="$(grep '^PORT=' "$DOT_ENV_FILE" | cut -d= -f2-)"
  _db_url="$(grep '^DATABASE_URL=' "$DOT_ENV_FILE" | cut -d= -f2-)"
  _api_key="$(grep '^EXTERNAL_API_KEY=' "$DOT_ENV_FILE" | cut -d= -f2-)"
  _gleap="$(grep '^GLEAP_API_KEY=' "$DOT_ENV_FILE" | cut -d= -f2-)"
  _enable="$(grep '^ENABLE_FEATURES=' "$DOT_ENV_FILE" | cut -d= -f2-)"
  _app_id="$(grep '^APP_ID=' "$DOT_ENV_FILE" | cut -d= -f2-)"
  _connstr="$(grep '^ConnectionStrings__Postgres=' "$DOT_ENV_FILE" | cut -d= -f2-)"
  _app_cfg="$(grep '^APP_CONFIG=' "$DOT_ENV_FILE" | cut -d= -f2- | sed 's/^"//;s/"$//' | sed 's/\\"/"/g')"
  check_val "01: PORT"                       "$PORT_EXPECTED"             "$_port"
  check_val "01: DATABASE_URL"               "$DATABASE_URL_EXPECTED"     "$_db_url"
  check_val "01: EXTERNAL_API_KEY"           "$EXTERNAL_API_KEY_EXPECTED" "$_api_key"
  check_val "01: GLEAP_API_KEY"              "$GLEAP_API_KEY_EXPECTED"    "$_gleap"
  check_val "01: ENABLE_FEATURES"            "$ENABLE_FEATURES_EXPECTED"  "$_enable"
  check_val "01: APP_ID"                     "$APP_ID_EXPECTED"           "$_app_id"
  check_val "01: ConnectionStrings__Postgres" "$CONNSTRING_EXPECTED"      "$_connstr"
  check_val "01: APP_CONFIG"                 "$APP_CONFIG_EXPECTED"       "$_app_cfg"
fi

# Run the app to verify it works with the .env file
if (cd "$SAMPLE_01" && BUNDLE_GEMFILE="$SAMPLE_01/Gemfile" "$BUNDLE" exec "$RUBY" app.rb 2>/dev/null | grep -q "PORT"); then
  pass "01: app.rb runs ok"
else
  fail "01: app.rb runs ok"
fi

# ── 02-process-inject ─────────────────────────────────────────────────────────
echo ""
echo "─── 02-process-inject ───────────────────────────────────────────────"
SAMPLE_02="$SAMPLES_DIR/02-process-inject"

# Use bella run with printenv to get the actual injected values
_env02="$(cd "$SAMPLE_02" && bella run --app ruby-02-process-inject -- printenv 2>/dev/null)" || true
check_val "02: PORT"                       "$PORT_EXPECTED"             "$(echo "$_env02" | grep '^PORT=' | cut -d= -f2-)"
check_val "02: DATABASE_URL"               "$DATABASE_URL_EXPECTED"     "$(echo "$_env02" | grep '^DATABASE_URL=' | cut -d= -f2-)"
check_val "02: EXTERNAL_API_KEY"           "$EXTERNAL_API_KEY_EXPECTED" "$(echo "$_env02" | grep '^EXTERNAL_API_KEY=' | cut -d= -f2-)"
check_val "02: GLEAP_API_KEY"              "$GLEAP_API_KEY_EXPECTED"    "$(echo "$_env02" | grep '^GLEAP_API_KEY=' | cut -d= -f2-)"
check_val "02: ENABLE_FEATURES"            "$ENABLE_FEATURES_EXPECTED"  "$(echo "$_env02" | grep '^ENABLE_FEATURES=' | cut -d= -f2-)"
check_val "02: APP_ID"                     "$APP_ID_EXPECTED"           "$(echo "$_env02" | grep '^APP_ID=' | cut -d= -f2-)"
check_val "02: ConnectionStrings__Postgres" "$CONNSTRING_EXPECTED"      "$(echo "$_env02" | grep '^ConnectionStrings__Postgres=' | cut -d= -f2-)"
_app_cfg02="$(echo "$_env02" | grep '^APP_CONFIG=' | cut -d= -f2- | sed 's/^"//;s/"$//' | sed 's/\\"/"/g')"
check_val "02: APP_CONFIG"                 "$APP_CONFIG_EXPECTED"       "$_app_cfg02"

# ── 03-standalone ─────────────────────────────────────────────────────────────
echo ""
echo "─── 03-standalone ───────────────────────────────────────────────────"
SAMPLE_03="$SAMPLES_DIR/03-standalone"

_output03="$(cd "$SAMPLE_03" && BUNDLE_GEMFILE="$SAMPLE_03/Gemfile" \
  bella exec --app ruby-03-standalone -- "$BUNDLE" exec "$RUBY" app.rb 2>/dev/null)" || true

check_contains "03: PORT in output"         "PORT" "$_output03"
check_contains "03: DATABASE_URL in output" "DATABASE_URL" "$_output03"
check_contains "03: EXTERNAL_API_KEY in output" "API_KEY" "$_output03"

# ── 05-typed-secrets ──────────────────────────────────────────────────────────
echo ""
echo "─── 05-typed-secrets ────────────────────────────────────────────────"
SAMPLE_05="$SAMPLES_DIR/05-typed-secrets"

_output05="$(cd "$SAMPLE_05" && BUNDLE_GEMFILE="$SAMPLE_05/Gemfile" bella run --app ruby-05-typed-secrets -- "$BUNDLE" exec "$RUBY" app.rb 2>/dev/null)" || true

# Check typed PORT (Integer)
_port05="$(echo "$_output05" | grep 'Int.*PORT' | grep -oE '[0-9]+'  | head -1)"
check_val "05: PORT (int)"        "$PORT_EXPECTED"             "$_port05"

# Check ENABLE_FEATURES (Bool)
_enable05="$(echo "$_output05" | grep 'Bool.*ENABLE' | grep -oE '(true|false)' | head -1)"
check_val "05: ENABLE_FEATURES (bool)" "$ENABLE_FEATURES_EXPECTED" "$_enable05"

# Check APP_ID (GUID)
_appid05="$(echo "$_output05" | grep 'GUID.*APP_ID' | cut -d: -f2- | xargs)"
check_val "05: APP_ID (uuid)"     "$APP_ID_EXPECTED"           "$_appid05"

# Check APP_CONFIG JSON fields
check_contains "05: APP_CONFIG setting1" '"value1"' "$_output05"
check_contains "05: APP_CONFIG setting2" '42' "$_output05"

# ── 04-rails ──────────────────────────────────────────────────────────────────
echo ""
echo "─── 04-rails ────────────────────────────────────────────────────────"
SAMPLE_04="$SAMPLES_DIR/04-rails"
RAILS_PORT=4568
RAILS_PID=""

# Kill any stale server already listening on this port, and remove stale PID file
_stale_pid="$(lsof -ti ":$RAILS_PORT" 2>/dev/null || true)"
[[ -n "$_stale_pid" ]] && kill "$_stale_pid" 2>/dev/null && sleep 1 || true
rm -f "$SAMPLE_04/tmp/pids/server.pid"

# Start Rails server via bella exec (Railtie loads secrets at boot)
(cd "$SAMPLE_04" && BUNDLE_GEMFILE="$SAMPLE_04/Gemfile" \
  bella exec --app ruby-04-rails -- "$BUNDLE" exec "$RUBY" bin/rails server \
    -p "$RAILS_PORT" -e development >/tmp/rails-test.log 2>&1) &
RAILS_PID=$!

# Wait up to 30s for server to be ready
_rails_ready=false
for i in $(seq 1 30); do
  if curl -sf "http://localhost:$RAILS_PORT/health" -o /dev/null 2>/dev/null; then
    _rails_ready=true; break
  fi
  sleep 1
done

if [[ "$_rails_ready" == "true" ]]; then
  pass "04-rails: server started"
  _secrets04="$(curl -sf "http://localhost:$RAILS_PORT/secrets" 2>/dev/null)" || true
  _typed04="$(curl -sf "http://localhost:$RAILS_PORT/typed" 2>/dev/null)" || true

  check_val "04 / PORT"                        "$PORT_EXPECTED"             "$(echo "$_secrets04" | /usr/bin/python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('PORT',''))" 2>/dev/null)"
  check_val "04 / DATABASE_URL"                "$DATABASE_URL_EXPECTED"     "$(echo "$_secrets04" | /usr/bin/python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('DATABASE_URL',''))" 2>/dev/null)"
  check_val "04 / EXTERNAL_API_KEY"            "$EXTERNAL_API_KEY_EXPECTED" "$(echo "$_secrets04" | /usr/bin/python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('EXTERNAL_API_KEY',''))" 2>/dev/null)"
  check_val "04 / GLEAP_API_KEY"               "$GLEAP_API_KEY_EXPECTED"    "$(echo "$_secrets04" | /usr/bin/python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('GLEAP_API_KEY',''))" 2>/dev/null)"
  check_val "04 / ENABLE_FEATURES"             "$ENABLE_FEATURES_EXPECTED"  "$(echo "$_secrets04" | /usr/bin/python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('ENABLE_FEATURES',''))" 2>/dev/null)"
  check_val "04 / APP_ID"                      "$APP_ID_EXPECTED"           "$(echo "$_secrets04" | /usr/bin/python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('APP_ID',''))" 2>/dev/null)"
  check_val "04 / ConnectionStrings__Postgres" "$CONNSTRING_EXPECTED"       "$(echo "$_secrets04" | /usr/bin/python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('ConnectionStrings__Postgres',''))" 2>/dev/null)"
  _app_cfg04="$(echo "$_secrets04" | /usr/bin/python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('APP_CONFIG',''))" 2>/dev/null)"
  check_val "04 / APP_CONFIG"                  "$APP_CONFIG_EXPECTED"       "$_app_cfg04"

  # /typed endpoint — AppSecrets module, proper types (not strings)
  _port_type="$(echo "$_typed04"    | /usr/bin/python3 -c "import sys,json; d=json.load(sys.stdin); v=d.get('PORT'); print(type(v).__name__)" 2>/dev/null)" || true
  _enable_type="$(echo "$_typed04" | /usr/bin/python3 -c "import sys,json; d=json.load(sys.stdin); v=d.get('ENABLE_FEATURES'); print(type(v).__name__)" 2>/dev/null)" || true
  check_val "04 /typed PORT (Integer)"          "$PORT_EXPECTED"             "$(echo "$_typed04" | /usr/bin/python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('PORT',''))" 2>/dev/null)"
  check_val "04 /typed PORT is JSON number"     "int"                        "$_port_type"
  check_val "04 /typed ENABLE_FEATURES (Bool)"  "$ENABLE_FEATURES_EXPECTED"  "$(echo "$_typed04" | /usr/bin/python3 -c "import sys,json; d=json.load(sys.stdin); print(str(d.get('ENABLE_FEATURES','')).lower())" 2>/dev/null)"
  check_val "04 /typed ENABLE_FEATURES is bool" "bool"                       "$_enable_type"
  check_val "04 /typed APP_ID"                  "$APP_ID_EXPECTED"           "$(echo "$_typed04" | /usr/bin/python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('APP_ID',''))" 2>/dev/null)"
  check_contains "04 /typed APP_CONFIG setting1" "value1"                    "$_typed04"
  check_contains "04 /typed APP_CONFIG setting2" "42"                        "$_typed04"
else
  fail "04-rails: server started -- did not respond within 30s"
  cat /tmp/rails-test.log 2>/dev/null | tail -20
fi

# Stop the Rails server (kill subshell + the actual process on the port)
[[ -n "$RAILS_PID" ]] && kill "$RAILS_PID" 2>/dev/null || true
_running="$(lsof -ti ":$RAILS_PORT" 2>/dev/null || true)"
[[ -n "$_running" ]] && kill "$_running" 2>/dev/null || true
wait "$RAILS_PID" 2>/dev/null || true
rm -f "$SAMPLE_04/tmp/pids/server.pid"


echo ""
echo "─── Summary ─────────────────────────────────────────────────────────"
for r in "${RESULTS[@]}"; do
  echo "  $r"
done
echo ""
printf "PASS: %d  FAIL: %d  TOTAL: %d\n" "$PASS" "$FAIL" "$((PASS+FAIL))"
[[ $FAIL -eq 0 ]]
