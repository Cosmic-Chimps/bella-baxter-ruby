# frozen_string_literal: true

require "logger"

require_relative "bella_baxter/version"
require_relative "bella_baxter/errors"
require_relative "bella_baxter/models"
require_relative "bella_baxter/e2ee"
require_relative "bella_baxter/client"
require_relative "bella_baxter/webhook_signature"

module BellaBaxter
  class << self
    # Optional global configuration.
    # When set, BellaBaxter.client uses it instead of ENV vars.
    attr_accessor :configuration

    def configure
      self.configuration ||= Configuration.new(
        baxter_url:   ENV.fetch("BELLA_BAXTER_URL", ""),
        api_key:      ENV.fetch("BELLA_API_KEY", ""),
        project:      ENV.fetch("BELLA_PROJECT", ""),
        environment:  ENV.fetch("BELLA_ENV", "")
      )
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

    # Called automatically by the Rails Railtie before_configuration hook.
    # Silently skips if BELLA_API_KEY is not set (no-op in dev without Bella).
    def auto_load_from_env!
      return unless ENV["BELLA_API_KEY"]

      c = config_from_env
      if c.baxter_url.empty?
        logger.warn "[BellaBaxter] BELLA_API_KEY set but BELLA_BAXTER_URL missing — skipping"
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

    def config_from_env
      Configuration.new(
        baxter_url: ENV.fetch("BELLA_BAXTER_URL", ""),
        api_key:    ENV.fetch("BELLA_API_KEY", "")
      )
    end

    def logger
      @logger ||= (defined?(Rails) && Rails.logger) || Logger.new($stdout)
    end
  end
end

# Auto-register Railtie when Rails is present.
require_relative "bella_baxter/railtie" if defined?(Rails::Railtie)
