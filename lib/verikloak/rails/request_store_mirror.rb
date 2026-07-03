# frozen_string_literal: true

require_relative 'railtie_logger'

module Verikloak
  module Rails
    # Rack middleware that mirrors the Verikloak request context from the
    # Rack env into +RequestStore+, so code running outside the controller
    # (service objects, jobs enqueued during the request) can read the same
    # values through the controller helpers' RequestStore fallback.
    #
    # The Railtie inserts this middleware right after +Verikloak::Middleware+
    # and only when the +request_store+ gem is loaded. Values are written on
    # every request (including +nil+ on skipped/unauthenticated paths) so no
    # stale context leaks between requests even before request_store's own
    # cleanup middleware runs. Applications that mirrored these keys by hand
    # before this middleware existed should remove their own writer — it
    # would otherwise be overwritten here.
    #
    # Mirroring is best-effort: a failure never breaks the request, but it
    # is logged (once per middleware instance) so a silently dead fallback
    # does not go unnoticed.
    class RequestStoreMirror
      # @param app [#call] next Rack application
      def initialize(app)
        @app = app
        @failure_warned = false
      end

      # Mirror claims/token into RequestStore, then call downstream.
      #
      # @param env [Hash] Rack environment
      # @return [Array] Rack response triple
      def call(env)
        mirror(env)
        @app.call(env)
      end

      private

      # Best-effort mirroring; never breaks the request.
      #
      # @param env [Hash]
      # @return [void]
      def mirror(env)
        return unless defined?(::RequestStore)

        config = Verikloak::Rails.config
        store = ::RequestStore.store
        store[:verikloak_user]  = env[config.effective_user_env_key]
        store[:verikloak_token] = env[config.effective_token_env_key]
      rescue StandardError => e
        warn_mirror_failure(e)
      end

      # Log the first mirroring failure so the RequestStore fallback does not
      # die silently; stay quiet afterwards to avoid flooding the log on
      # every request.
      #
      # @param error [StandardError]
      # @return [void]
      def warn_mirror_failure(error)
        return if @failure_warned

        @failure_warned = true
        RailtieLogger.warn(
          "[verikloak] RequestStoreMirror could not mirror the request context: #{error.class}: #{error.message}"
        )
      end
    end
  end
end
