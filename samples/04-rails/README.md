# Rails + Bella Baxter

Zero-secret Rails: `DATABASE_URL`, `SECRET_KEY_BASE`, and every other credential live in Bella Baxter. Nothing sensitive lives in your repo or your hosting platform's environment variable UI.

## How it works

The gem ships a **Railtie** that hooks into `before_configuration` — Rails' earliest boot hook, before `database.yml` is evaluated and before any initializers run.

```
Rails boot order:
  1. Gemfile loaded → bella_baxter gem auto-registers Railtie
  2. config/application.rb starts
  3. [before_configuration] ← Railtie calls /api/v1/keys/me, injects secrets into ENV
  4. database.yml evaluated ← ENV["DATABASE_URL"] is now available
  5. config/initializers/*.rb run
  6. App starts
```

## Setup

**Gemfile**

```ruby
gem "bella_baxter"
```

**Run with bella exec** (the only secrets you need to configure in your platform):

```bash
bella exec -- bundle exec rails server
```

`bella exec` injects exactly two credentials:

| Variable          | Description                        |
|-------------------|------------------------------------|
| `BELLA_API_KEY`   | API key (`bax-...`)                |
| `BELLA_BAXTER_URL`| URL of your Bella Baxter instance  |

That's it. Project slug, environment, and E2EE are **auto-discovered** from the API key via `/api/v1/keys/me`. You don't set them manually.

## What gets loaded

Everything you've stored in Bella Baxter for that project + environment is injected into `ENV` before Rails reads any config:

```
DATABASE_URL         → ENV → database.yml picks it up automatically
REDIS_URL            → ENV → config/cable.yml or initializers pick it up
SECRET_KEY_BASE      → ENV → Rails uses it automatically
STRIPE_SECRET_KEY    → ENV → use ENV["STRIPE_SECRET_KEY"] anywhere
```

## config/initializers/bella_baxter.rb

Secrets are already in `ENV` by the time initializers run. This file is for **optional** use cases:

```ruby
# Reload secrets at runtime (e.g. after a secret rotation, without restarting):
count = BellaBaxter.load_into_env!(overwrite: true)
Rails.logger.info "Reloaded #{count} secrets from Bella Baxter"

# Access the client directly for writes or advanced reads:
client = BellaBaxter::Client.from_env
client.create_secret(key: "NEW_KEY", value: "new-value")
```

## database.yml pattern

Nothing secret in the file:

```yaml
production:
  adapter: postgresql
  url: <%= ENV.fetch("DATABASE_URL") %>
```

`DATABASE_URL` was injected by Bella Baxter at step 3. Rails reads it at step 4. Clean.
