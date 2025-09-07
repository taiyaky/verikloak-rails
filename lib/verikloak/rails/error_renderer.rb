# frozen_string_literal: true

module Verikloak
  module Rails
    # Renders JSON errors for authentication/authorization failures.
    #
    # When status is 401, adds a `WWW-Authenticate: Bearer` header including
    # `error` and `error_description` fields when available.
    class ErrorRenderer
      DEFAULT_STATUS_MAP = {
        'invalid_token' => 401,
        'unauthorized' => 401,
        'forbidden' => 403,
        'jwks_fetch_failed' => 503,
        'jwks_parse_failed' => 503,
        'discovery_metadata_fetch_failed' => 503,
        'discovery_metadata_invalid' => 503
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
        headers = {}
        if status == 401
          hdr = +'Bearer'
          hdr << %( error="#{code}") if code
          hdr << %( error_description="#{message}") if message
          headers['WWW-Authenticate'] = hdr
        end
        headers.each { |k, v| controller.response.set_header(k, v) }
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
    end
  end
end
