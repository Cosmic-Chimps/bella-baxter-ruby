# frozen_string_literal: true

require_relative "client"

module BellaBaxter
  # Rails Railtie — automatically loads secrets into ENV before Rails
  # reads database.yml, cache config, and config/initializers/*.
  #
  # == How it works
  #
  # +config.before_configuration+ is Rails' earliest boot hook. Bella Baxter
  # calls /api/v1/keys/me to discover which project/environment the API key
  # belongs to, fetches all secrets, and injects them into ENV — before
  # database.yml is evaluated.
  #
  # == Setup
  #
  #   # Gemfile
  #   gem "bella_baxter"
  #
  #   # Start your app
  #   bella sdk run -- bundle exec rails server
  #
  # That's it. The Railtie auto-registers when the gem is loaded.
  #
  # == Required environment variables (set by `bella sdk run`)
  #
  #   BELLA_BAXTER_API_KEY   Your API key (bax-...); the deprecated BELLA_API_KEY is still read
  #   BELLA_BAXTER_URL       Base URL of your Bella Baxter instance; the deprecated BELLA_API_URL is still read
  #
  # With no API key the Railtie logs one warning naming those variables and loads nothing. It has no
  # bearer-token mode: BELLA_BAXTER_ACCESS_TOKEN (what +bella sdk run+ injects when signed in as a person)
  # is not a credential this gem can use, and the warning says so.
  #
  # Project slug, environment slug, and E2EE are auto-discovered from the
  # API key — you do not set them manually.
  #
  # == config/initializers/bella_baxter.rb
  #
  # Secrets are already in ENV by the time initializers run. That file is
  # for optional patterns only (hot-reload, health checks, etc.).
  #
  class Railtie < ::Rails::Railtie
    config.before_configuration do
      BellaBaxter.auto_load_from_env!
    end
  end
end
