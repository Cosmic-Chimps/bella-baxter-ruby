# frozen_string_literal: true

require "logger"

require_relative "bella_baxter/version"
require_relative "bella_baxter/errors"
require_relative "bella_baxter/models"
require_relative "bella_baxter/e2ee"
require_relative "bella_baxter/client"
require_relative "bella_baxter/webhook_signature"

module BellaBaxter
  # The names the gem reads, canonical first. +bella sdk run+ injects the canonical names AND the deprecated
  # aliases, so both work under it; a host configured by hand follows the documentation (#1483).
  API_KEY_VARIABLES = %w[BELLA_BAXTER_API_KEY BELLA_API_KEY].freeze
  URL_VARIABLES     = %w[BELLA_BAXTER_URL BELLA_API_URL].freeze

  class << self
    # Optional global configuration.
    # When set, BellaBaxter.client uses it instead of ENV vars.
    attr_accessor :configuration

    def configure
      # #1162: Configuration has no project/environment members (they come from the API key), so passing
      # them here raised ArgumentError on the first `configure` call.
      self.configuration ||= config_from_env
      yield configuration
      self
    end

    # Returns a singleton client built from the global configuration.
    # @return [BellaBaxter::Client]
    def client
      @client ||= Client.new(config: configuration || config_from_env)
    end

    # Shorthand: fetch all secrets and inject into ENV.
    # Existing ENV values are NOT overwritten unless overwrite: true.
    #
    # @return [Integer] number of secrets injected
    def load_into_env!(overwrite: false)
      client.load_into_env!(overwrite: overwrite)
    end

    # The API key from the environment: +BELLA_BAXTER_API_KEY+, else the deprecated +BELLA_API_KEY+.
    # @return [String, nil] nil when neither is set to something non-empty
    def env_api_key
      first_env(API_KEY_VARIABLES)
    end

    # The Baxter address from the environment: +BELLA_BAXTER_URL+, else the deprecated +BELLA_API_URL+.
    # @return [String, nil]
    def env_baxter_url
      first_env(URL_VARIABLES)
    end

    # Called automatically by the Rails Railtie before_configuration hook.
    # Skips (with ONE warning that names the variables it looked for, never a value) when there is no
    # credential, so an app configured with a name the gem does not read says so instead of booting
    # without its secrets in silence.
    def auto_load_from_env!
      unless env_api_key
        logger.warn no_credential_message
        return
      end

      c = config_from_env
      if c.baxter_url.empty?
        logger.warn "[BellaBaxter] An API key is set but no address (#{URL_VARIABLES.join(' or ')}) — skipping"
        return
      end

      begin
        client = Client.new(config: c, private_key: ENV["BELLA_BAXTER_PRIVATE_KEY"])
        count  = client.load_into_env!
        ctx    = client.key_context
        logger.info "[BellaBaxter] Loaded #{count} secret(s) into ENV " \
                    "(project=#{ctx['projectSlug']} env=#{ctx['environmentSlug']})"
      rescue BellaBaxter::Error => e
        logger.warn "[BellaBaxter] Failed to load secrets: #{e.message}"
      end
    end

    private

    def first_env(names)
      names.each do |name|
        value = ENV.fetch(name, nil)
        return value unless value.nil? || value.empty?
      end
      nil
    end

    def no_credential_message
      message = "[BellaBaxter] No API key found (looked for #{API_KEY_VARIABLES.join(', ')}) — secrets were not loaded."
      if first_env(["BELLA_BAXTER_ACCESS_TOKEN"])
        message += " BELLA_BAXTER_ACCESS_TOKEN is set, but this gem signs requests with an API key (bax-...) " \
                   "and has no bearer-token mode; run with an API key."
      end
      message
    end

    def config_from_env
      Configuration.new(
        baxter_url: env_baxter_url || "",
        api_key:    env_api_key || ""
      )
    end

    def logger
      @logger ||= (defined?(Rails) && Rails.logger) || Logger.new($stdout)
    end
  end
end

# Auto-register Railtie when Rails is present.
require_relative "bella_baxter/railtie" if defined?(Rails::Railtie)
