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
  #   bella exec -- bundle exec rails server
  #
  # That's it. The Railtie auto-registers when the gem is loaded.
  #
  # == Required environment variables (set by `bella exec`)
  #
  #   BELLA_API_KEY      Your API key (bax-...)
  #   BELLA_BAXTER_URL   Base URL of your Bella Baxter instance
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
