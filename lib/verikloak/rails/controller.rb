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
          rescue_from StandardError do |_e|
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
      # @example
      #   with_required_audience!('my-api', 'payments')
      def with_required_audience!(*required)
        aud = Array(current_user_claims&.dig('aud'))
        return if required.flatten.all? { |r| aud.include?(r) }

        render json: { error: 'forbidden', message: 'Required audience not satisfied' }, status: :forbidden
      end

      private

      # Wraps the request in tagged logs for request ID and subject when available.
      # @yieldreturn [Object] result of the block
      # @return [Object]
      def _verikloak_tag_logs(&)
        tags = []
        if Verikloak::Rails.config.logger_tags.include?(:request_id)
          rid = request.request_id || request.headers['X-Request-Id']
          tags << "req:#{rid}" if rid
        end
        tags << "sub:#{current_subject}" if Verikloak::Rails.config.logger_tags.include?(:sub) && current_subject
        if ::Rails.logger.respond_to?(:tagged) && tags.any?
          ::Rails.logger.tagged(*tags, &)
        else
          yield
        end
      end
    end
  end
end
