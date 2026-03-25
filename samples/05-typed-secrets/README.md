# Sample 05: Typed Secrets (`bella secrets generate ruby`)

**Pattern:** `bella secrets generate ruby` → typed accessor module → no more `ENV["TYPO"]`

---

## How it works

```
bella secrets generate ruby -o secrets.rb
↓
secrets.rb  (generated, safe to commit — contains NO secret values)
↓
require_relative 'secrets'
↓
AppSecrets.database_url  (typed, IDE-autocomplete, runtime validation)
```

## Setup

```bash
# Install dependencies
bundle install

# Authenticate
bella login --api-key bax-xxxxxxxxxxxxxxxxxxxx

export BELLA_BAXTER_URL=http://localhost:5522   # your Bella Baxter instance

# Generate the typed module (re-run whenever secrets change)
bella secrets generate ruby -o secrets.rb

# Pull actual secret values into environment
bella secrets get -o .env

# Run the app
bella run -- bundle exec ruby app.rb
```

## Why use typed secrets?

- **Type safety** — `PORT` is an `Integer`, not a string you forget to parse
- **IDE autocomplete** — `AppSecrets.` shows all available secrets
- **Fail-fast validation** — missing secrets raise at startup, not in production
- **Safe to commit** — generated file contains NO secret values, just key names and types

## What's generated

`bella secrets generate ruby` reads your project's secret manifest and emits `secrets.rb`:

| Secret               | Type      | Accessor                          |
|----------------------|-----------|-----------------------------------|
| `PORT`               | `Integer` | `AppSecrets.port`                 |
| `DATABASE_URL`       | `URI`     | `AppSecrets.database_url`         |
| `EXTERNAL_API_KEY`   | `String`  | `AppSecrets.external_api_key`     |
| `ENABLE_FEATURE_FLAGS` | `TrueClass`/`FalseClass` | `AppSecrets.enable_feature_flags` |
| `SIGNING_KEY`        | `String` (binary) | `AppSecrets.signing_key`   |

## Regenerate after adding secrets

```bash
bella secrets generate ruby -o secrets.rb
git add secrets.rb  # safe — no values
```
