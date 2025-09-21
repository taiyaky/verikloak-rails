# frozen_string_literal: true

require 'active_support/concern'

module Verikloak
  module Rails
    # Controller concern providing Verikloak helpers and JSON error handling.
    #
    # Includes `before_action :authenticate_user!`, helpers such as
    # `current_user_claims`, and consistent 401/403 responses. Optionally wraps
    # requests with tagged logging and a 500 JSON renderer.
    module Controller
      extend ActiveSupport::Concern

      included do
        before_action :authenticate_user!
        # Register generic error handler first so specific handlers take precedence.
        if Verikloak::Rails.config.render_500_json
          rescue_from StandardError do |e|
            _verikloak_log_internal_error(e)
            render json: { error: 'internal_server_error', message: 'An unexpected error occurred' },
                   status: :internal_server_error
          end
        end
        if defined?(::Pundit::NotAuthorizedError) && Verikloak::Rails.config.rescue_pundit
          rescue_from ::Pundit::NotAuthorizedError do |e|
            render json: { error: 'forbidden', message: e.message }, status: :forbidden
          end
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
        return if authenticated?

        e = begin
          ::Verikloak::Error.new('unauthorized')
        rescue StandardError
          StandardError.new('Unauthorized')
        end
        Verikloak::Rails.config.error_renderer.render(self, e)
      end

      # Whether the request has verified user claims.
      # @return [Boolean]
      def authenticated? = current_user_claims.present?

      # The verified JWT claims for the current user.
      # Prefer Rack env; fall back to RequestStore when available.
      # @return [Hash, nil]
      def current_user_claims
        env_claims = request.env['verikloak.user']
        return env_claims unless env_claims.nil?
        return ::RequestStore.store[:verikloak_user] if defined?(::RequestStore) && ::RequestStore.respond_to?(:store)

        nil
      end

      # The raw bearer token used for the current request.
      # Prefer Rack env; fall back to RequestStore when available.
      # @return [String, nil]
      def current_token
        env_token = request.env['verikloak.token']
        return env_token unless env_token.nil?
        return ::RequestStore.store[:verikloak_token] if defined?(::RequestStore) && ::RequestStore.respond_to?(:store)

        nil
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

        raise ::Verikloak::Error.new('forbidden', 'Required audience not satisfied')
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
        tags = []
        if Verikloak::Rails.config.logger_tags.include?(:request_id)
          rid = request.request_id || request.headers['X-Request-Id']
          rid = rid.to_s.gsub(/[\r\n]+/, ' ')
          tags << "req:#{rid}" unless rid.empty?
        end
        if Verikloak::Rails.config.logger_tags.include?(:sub)
          sub = current_subject
          if sub
            sanitized = sub.to_s.gsub(/[[:cntrl:]]+/, ' ').strip
            tags << "sub:#{sanitized}" unless sanitized.empty?
          end
        end
        tags
      end

      # Write StandardError details to the controller or Rails logger when
      # rendering the generic 500 JSON response. Logging ensures the
      # underlying failure is still visible to operators even though the
      # response body is static.
      #
      # @param exception [Exception]
      # @return [void]
      def _verikloak_log_internal_error(exception)
        target_logger = _verikloak_base_logger
        return unless target_logger.respond_to?(:error)

        target_logger.error("[Verikloak] #{exception.class}: #{exception.message}")
        backtrace = exception.backtrace
        target_logger.error(backtrace.join("\n")) if backtrace&.any?
      rescue StandardError
        # Never allow logging failures to interfere with request handling.
        nil
      end

      # Locate the innermost logger that responds to `error`.
      # @return [Object, nil]
      def _verikloak_base_logger
        root_logger = if defined?(::Rails) && ::Rails.respond_to?(:logger)
                        ::Rails.logger
                      elsif respond_to?(:logger)
                        logger
                      end
        current = root_logger
        while current.respond_to?(:logger)
          next_logger = current.logger
          break if next_logger.nil? || next_logger.equal?(current)

          current = next_logger
        end
        current
      end
    end
  end
end
