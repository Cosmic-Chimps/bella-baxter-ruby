# frozen_string_literal: true
require_relative "boot"

require "action_controller/railtie"

Bundler.require(*Rails.groups)

module BellaRailsSample
  class Application < Rails::Application
    config.load_defaults 8.1
    config.api_only = true
    config.logger = Logger.new($stdout)
    config.log_level = :info
    config.autoload_paths << Rails.root.join("app/lib")
  end
end
