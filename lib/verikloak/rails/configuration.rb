# frozen_string_literal: true

module Verikloak
  module Rails
    # Configuration for verikloak-rails.
    #
    # Controls how the Rack middleware is initialized (discovery, audience,
    # issuer, leeway, skip paths) and Rails-specific behavior such as
    # controller inclusion, logging tags, and error rendering.
    #
    # @!attribute [rw] discovery_url
    #   OIDC discovery document URL.
    #   @return [String, nil]
    # @!attribute [rw] audience
    #   Expected audience (`aud`) claim. Accepts String or Array.
    #   @return [String, Array<String>, nil]
    # @!attribute [rw] issuer
    #   Expected issuer (`iss`) claim.
    #   @return [String, nil]
    # @!attribute [rw] leeway
    #   Clock skew allowance in seconds.
    #   @return [Integer]
    # @!attribute [rw] skip_paths
    #   Paths to skip verification.
    #   @return [Array<String>]
    # @!attribute [rw] logger_tags
    #   Log tags to include (supports :request_id, :sub).
    #   @return [Array<Symbol>]
    # @!attribute [rw] error_renderer
    #   Custom error renderer object responding to `render(controller, error)`.
    #   @return [Object]
    # @!attribute [rw] auto_include_controller
    #   Auto-include the controller concern into ActionController::Base.
    #   @return [Boolean]
    # @!attribute [rw] render_500_json
    #   Rescue StandardError and render a JSON 500 response.
    #   @return [Boolean]
    # @!attribute [rw] rescue_pundit
    #   Rescue `Pundit::NotAuthorizedError` and render JSON 403 responses.
    #   @return [Boolean]
    # @!attribute [rw] middleware_insert_before
    #   Rack middleware to insert `Verikloak::Middleware` before.
    #   @return [Object, String, Symbol, nil]
    # @!attribute [rw] middleware_insert_after
    #   Rack middleware to insert `Verikloak::Middleware` after.
    #   @return [Object, String, Symbol, nil]
    # @!attribute [rw] auto_insert_bff_header_guard
    #   Auto-insert `Verikloak::Bff::HeaderGuard` when available.
    #   @return [Boolean]
    # @!attribute [rw] bff_header_guard_insert_before
    #   Rack middleware to insert the header guard before.
    #   @return [Object, String, Symbol, nil]
    # @!attribute [rw] bff_header_guard_insert_after
    #   Rack middleware to insert the header guard after.
    #   @return [Object, String, Symbol, nil]
    class Configuration
      attr_accessor :discovery_url, :audience, :issuer, :leeway, :skip_paths,
                    :logger_tags, :error_renderer, :auto_include_controller,
                    :render_500_json, :rescue_pundit,
                    :middleware_insert_before, :middleware_insert_after,
                    :auto_insert_bff_header_guard,
                    :bff_header_guard_insert_before, :bff_header_guard_insert_after

      # Initialize configuration with sensible defaults for Rails apps.
      # @return [void]
      def initialize
        @discovery_url = nil
        @audience      = 'rails-api'
        @issuer        = nil
        @leeway        = 60
        @skip_paths    = ['/up', '/health', '/rails/health']
        @logger_tags    = %i[request_id sub]
        @error_renderer = Verikloak::Rails::ErrorRenderer.new
        @auto_include_controller = true
        @render_500_json = false
        @rescue_pundit = true
        @middleware_insert_before = nil
        @middleware_insert_after = nil
        @auto_insert_bff_header_guard = true
        @bff_header_guard_insert_before = nil
        @bff_header_guard_insert_after = nil
      end

      # Options forwarded to the base Verikloak Rack middleware.
      # @return [Hash]
      # @example
      #   Verikloak::Rails.config.middleware_options
      #   #=> { discovery_url: 'https://example/.well-known/openid-configuration', leeway: 60, ... }
      def middleware_options
        {
          discovery_url: discovery_url,
          audience: audience,
          issuer: issuer,
          leeway: leeway,
          skip_paths: skip_paths
        }
      end
    end
  end
end
