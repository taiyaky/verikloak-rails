# frozen_string_literal: true

require 'active_support/concern'
require_relative 'controller/error_handling'

module Verikloak
  module Rails
    # Controller concern providing Verikloak helpers and JSON error handling.
    #
    # Includes `before_action :authenticate_user!`, helpers such as
    # `current_user_claims`, and consistent 401/403 responses. Optionally wraps
    # requests with tagged logging and a 500 JSON renderer.
    module Controller
      extend ActiveSupport::Concern

      # Rescue handlers and 500-error logging (kept in a separate module so
      # the concern itself stays focused on wiring and public helpers).
      include ErrorHandling

      included do
        before_action :authenticate_user!
        # Handlers are only registered when enabled at include time: a
        # registered-but-disabled `rescue_from StandardError` would suppress
        # ActiveSupport::Rescuable's `exception.cause` traversal and shadow
        # handlers registered earlier on the same class (re-raising from
        # inside a handler consults no other handler). The Railtie fires the
        # auto-include hook after `verikloak.configure`, so these flags are
        # final here; the same applies to `defined?(::Pundit::NotAuthorizedError)`,
        # which requires Pundit to be loaded before this concern is included.
        # Generic handler first so specific handlers take precedence.
        rescue_from StandardError, with: :_verikloak_handle_standard_error if Verikloak::Rails.config.render_500_json
        if defined?(::Pundit::NotAuthorizedError) && Verikloak::Rails.config.rescue_pundit
          rescue_from ::Pundit::NotAuthorizedError, with: :_verikloak_handle_pundit_error
        end
        rescue_from ::Verikloak::Error do |e|
          Verikloak::Rails.config.error_renderer.render(self, e)
        end
        around_action :_verikloak_tag_logs
      end

      # Ensures a user is authenticated, otherwise renders a JSON 401 response.
      #
      # @return [void]
      # @example In a controller
      #   class ApiController < ApplicationController
      #     before_action :authenticate_user!
      #   end
      def authenticate_user!
        return if Verikloak::Rails.config.skip_path_matcher.skip?(request.path_info)
        return if authenticated?

        e = ::Verikloak::Error.new('Unauthorized', code: 'unauthorized')
        Verikloak::Rails.config.error_renderer.render(self, e)
      end

      # Whether the request has verified user claims.
      # @return [Boolean]
      def authenticated? = current_user_claims.present?

      # The verified JWT claims for the current user.
      # Prefer Rack env (honoring a custom `user_env_key`); fall back to
      # RequestStore when available.
      # @return [Hash, nil]
      def current_user_claims
        _verikloak_fetch_request_context(Verikloak::Rails.config.effective_user_env_key, :verikloak_user)
      end

      # The raw bearer token used for the current request.
      # Prefer Rack env (honoring a custom `token_env_key`); fall back to
      # RequestStore when available.
      # @return [String, nil]
      def current_token
        _verikloak_fetch_request_context(Verikloak::Rails.config.effective_token_env_key, :verikloak_token)
      end

      # The `sub` (subject) claim from the current user claims.
      # @return [String, nil]
      def current_subject = current_user_claims && current_user_claims['sub']

      # Enforces that the current user has all required audiences.
      #
      # @param required [Array<String>] one or more audiences to require
      # @return [void]
      # @raise [Verikloak::Error] when the required audience is missing
      # @example
      #   with_required_audience!('my-api', 'payments')
      def with_required_audience!(*required)
        aud = Array(current_user_claims&.dig('aud'))
        return if required.flatten.all? { |r| aud.include?(r) }

        raise ::Verikloak::Error.new('Required audience not satisfied', code: 'forbidden')
      end

      private

      # Wraps the request in tagged logs for request ID and subject when available.
      # @yieldreturn [Object] result of the block
      # @return [Object]
      def _verikloak_tag_logs(&)
        tags = _verikloak_build_log_tags
        if ::Rails.logger.respond_to?(:tagged) && tags.any?
          ::Rails.logger.tagged(*tags, &)
        else
          yield
        end
      end

      # Build log tags from request context with minimal branching and safe values.
      # @return [Array<String>]
      def _verikloak_build_log_tags
        config = Verikloak::Rails.config
        tags = []
        if config.logger_tags.include?(:request_id)
          rid = _verikloak_sanitize_tag(request.request_id || request.headers['X-Request-Id'])
          tags << "req:#{rid}" if rid
        end
        if config.logger_tags.include?(:sub)
          sub = _verikloak_sanitize_tag(current_subject)
          tags << "sub:#{sub}" if sub
        end
        tags
      end

      # Strip control characters and surrounding whitespace from a log tag value.
      # @param value [Object, nil]
      # @return [String, nil] sanitized value, or nil when blank
      def _verikloak_sanitize_tag(value)
        sanitized = value.to_s.gsub(/[[:cntrl:]]+/, ' ').strip
        sanitized.empty? ? nil : sanitized
      end

      # Retrieve request context from Rack env or RequestStore.
      # @param env_key [String]
      # @param store_key [Symbol]
      # @return [Object, nil]
      def _verikloak_fetch_request_context(env_key, store_key)
        env_value = request.env[env_key]
        return env_value unless env_value.nil?
        return unless defined?(::RequestStore) && ::RequestStore.respond_to?(:store)

        store = ::RequestStore.store
        return unless store.respond_to?(:[])

        store[store_key]
      end
    end
  end
end
