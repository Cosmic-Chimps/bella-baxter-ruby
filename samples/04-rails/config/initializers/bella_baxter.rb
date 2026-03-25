# frozen_string_literal: true

# config/initializers/bella_baxter.rb
#
# By the time this file runs, the Railtie has already loaded all secrets into
# ENV (in the before_configuration hook). You do NOT need to call anything here
# for normal operation — just use ENV["MY_SECRET"] or Rails.application.config
# as usual.
#
# This file is a place for OPTIONAL advanced patterns:

# ── 1. Verify secrets loaded (useful in staging/production) ──────────────────
#
# if (count = ENV.select { |k, _| !k.start_with?("BELLA_") }.size) < 5
#   raise "Expected secrets from Bella Baxter but ENV looks empty (#{count} keys)"
# end

# ── 2. Expose the number of loaded secrets in a health check ─────────────────
#
# Rails.application.config.bella_secrets_loaded = BellaBaxter.client.key_context

# ── 3. Reload secrets without a server restart (e.g. after rotation) ─────────
#
# ActiveSupport::Reloader.to_prepare do
#   if Rails.env.production? && Time.now.min == 0  # every hour
#     count = BellaBaxter.load_into_env!(overwrite: true)
#     Rails.logger.info "[BellaBaxter] Hot-reloaded #{count} secret(s)"
#   end
# end

# ── Nothing to do in normal operation ────────────────────────────────────────
Rails.logger.debug "[BellaBaxter] Secrets already in ENV (loaded by Railtie at before_configuration)"
