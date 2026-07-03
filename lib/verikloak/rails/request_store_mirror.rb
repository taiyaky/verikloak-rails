# frozen_string_literal: true

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
    # cleanup middleware runs.
    class RequestStoreMirror
      # @param app [#call] next Rack application
      def initialize(app)
        @app = app
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
        return unless defined?(::RequestStore) && ::RequestStore.respond_to?(:store)

        store = ::RequestStore.store
        return unless store.respond_to?(:[]=)

        config = Verikloak::Rails.config
        store[:verikloak_user]  = env[config.effective_user_env_key]
        store[:verikloak_token] = env[config.effective_token_env_key]
      rescue StandardError
        nil
      end
    end
  end
end
