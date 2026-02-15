# frozen_string_literal: true

require 'verikloak/error_response'

module Verikloak
  module Rails
    # Renders JSON errors for authentication/authorization failures.
    #
    # When status is 401, adds a `WWW-Authenticate: Bearer` header including
    # `error` and `error_description` fields when available.
    #
    # Header sanitization is delegated to {Verikloak::ErrorResponse} to ensure
    # consistent control-character stripping across all Verikloak gems.
    class ErrorRenderer
      DEFAULT_STATUS_MAP = {
        'invalid_token' => 401,
        'unauthorized' => 401,
        'forbidden' => 403,
        'jwks_fetch_failed' => 503,
        'jwks_parse_failed' => 503,
        'discovery_metadata_fetch_failed' => 503,
        'discovery_metadata_invalid' => 503,
        # Additional infrastructure/configuration errors from core
        'invalid_discovery_url' => 503,
        'discovery_redirect_error' => 503
      }.freeze

      # Render an error as JSON, adding `WWW-Authenticate` when appropriate.
      #
      # @param controller [#response,#render] a Rails controller instance
      # @param error [Exception] the error to render
      # @return [void]
      # @example
      #   begin
      #     do_auth!
      #   rescue Verikloak::Error => e
      #     Verikloak::Rails.config.error_renderer.render(self, e)
      #   end
      def render(controller, error)
        code, message = extract_code_message(error)
        status = status_for(error, code)
        auth_headers(status, code, message).each do |header, value|
          controller.response.set_header(header, value)
        end
        controller.render json: { error: code || 'unauthorized', message: message }, status: status
      end

      private

      # Extract error code and message from a given exception.
      # @param error [Exception]
      # @return [Array<(String, String)>]
      def extract_code_message(error)
        code = if error.respond_to?(:code) && error.code
                 error.code
               else
                 error.class.name.split('::').last.gsub(/Error$/, '').downcase
               end
        [code, error.message.to_s]
      end

      # Map an error to an HTTP status code.
      # @param error [Exception]
      # @param code [String, nil]
      # @return [Integer]
      def status_for(error, code)
        if error.is_a?(::Verikloak::Error)
          DEFAULT_STATUS_MAP[code] || 401
        else
          401
        end
      end

      # Build WWW-Authenticate headers when returning 401 responses.
      # Delegates sanitization to {Verikloak::ErrorResponse.sanitize_header_value}
      # to ensure control-character stripping is consistent with the core gem.
      # @param status [Integer]
      # @param code [String, nil]
      # @param message [String]
      # @return [Hash<String, String>]
      def auth_headers(status, code, message)
        return {} unless status == 401

        sanitize = ->(v) { Verikloak::ErrorResponse.sanitize_header_value(v) }
        header = +'Bearer'
        header << %( error="#{sanitize.call(code)}") if code
        header << %( error_description="#{sanitize.call(message)}") if message
        { 'WWW-Authenticate' => header }
      end
    end
  end
end
