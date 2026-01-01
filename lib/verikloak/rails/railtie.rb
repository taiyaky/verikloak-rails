# frozen_string_literal: true

require 'rails/railtie'
require 'verikloak/middleware'
require_relative 'railtie_logger'
require_relative 'bff_configurator'

module Verikloak
  module Rails
    # Hooks verikloak-rails into a Rails application lifecycle.
    #
    # - Applies configuration from `config.verikloak`
    # - Inserts base `Verikloak::Middleware`
    # - Auto-includes controller concern when enabled
    class Railtie < ::Rails::Railtie
      CONFIG_KEYS = %i[
        discovery_url audience issuer leeway skip_paths
        logger_tags error_renderer auto_include_controller
        render_500_json rescue_pundit middleware_insert_before
        middleware_insert_after auto_insert_bff_header_guard
        bff_header_guard_insert_before bff_header_guard_insert_after
        token_verify_options decoder_cache_limit token_env_key user_env_key
        bff_header_guard_options
      ].freeze

      config.verikloak = ActiveSupport::OrderedOptions.new

      # Apply configuration and insert middleware.
      # Runs after config/initializers/*.rb so user settings take effect.
      # @return [void]
      initializer 'verikloak.configure', after: :load_config_initializers do |app|
        ::Verikloak::Rails::Railtie.send(:configure_middleware, app)
      end

      # Optionally include the controller concern when ActionController loads.
      # Supports both ActionController::Base and ActionController::API (API mode).
      # Skips inclusion if the controller already includes the concern.
      # @return [void]
      initializer 'verikloak.controller' do |_app|
        %i[action_controller_base action_controller_api].each do |hook|
          ActiveSupport.on_load(hook) do
            next if include?(Verikloak::Rails::Controller) # Already included, skip

            include Verikloak::Rails::Controller if Verikloak::Rails.config.auto_include_controller
          end
        end
      end

      class << self
        private

        # Apply configured options and insert the base middleware into the stack.
        #
        # @param app [Rails::Application] application being initialized
        # @return [ActionDispatch::MiddlewareStackProxy] configured middleware stack
        def configure_middleware(app)
          apply_configuration(app)
          BffConfigurator.configure_library

          unless discovery_url_present?
            log_missing_discovery_url_warning
            return
          end

          stack = insert_base_middleware(app)
          BffConfigurator.configure_bff_guard(stack) if stack

          stack
        end

        # Check if discovery_url is present and valid.
        #
        # @return [Boolean] true if discovery_url is configured and not empty
        def discovery_url_present?
          discovery_url = Verikloak::Rails.config.discovery_url
          return false unless discovery_url

          return !discovery_url.blank? if discovery_url.respond_to?(:blank?)
          return !discovery_url.empty? if discovery_url.respond_to?(:empty?)

          true
        end

        # Log a warning message when discovery_url is missing.
        # Uses Rails.logger if available, falls back to warn.
        #
        # @return [void]
        def log_missing_discovery_url_warning
          message = '[verikloak] discovery_url is not configured; skipping middleware insertion.'
          RailtieLogger.warn(message)
        end

        # Sync configuration from the Rails application into Verikloak::Rails.
        #
        # @param app [Rails::Application]
        # @return [void]
        def apply_configuration(app)
          Verikloak::Rails.configure do |c|
            rails_cfg = app.config.verikloak
            CONFIG_KEYS.each do |key|
              c.send("#{key}=", rails_cfg[key]) if rails_cfg.key?(key)
            end
            c.rescue_pundit = false if !rails_cfg.key?(:rescue_pundit) && defined?(::Verikloak::Pundit)
          end
        end

        # Insert the base Verikloak::Middleware into the application middleware stack.
        # Respects the configured insertion point (before or after specified middleware).
        #
        # @param app [Rails::Application] the Rails application
        # @return [ActionDispatch::MiddlewareStackProxy] the configured middleware stack
        def insert_base_middleware(app)
          stack = app.middleware
          base_options = Verikloak::Rails.config.middleware_options

          if (before = Verikloak::Rails.config.middleware_insert_before)
            stack.insert_before before,
                                ::Verikloak::Middleware,
                                **base_options
          else
            insert_middleware_after(stack, base_options)
          end

          stack
        end

        # Insert middleware after a specified middleware or at the default position.
        # Handles the case where no specific insertion point is configured.
        #
        # @param stack [ActionDispatch::MiddlewareStackProxy] the middleware stack
        # @param base_options [Hash] options to pass to the middleware
        # @return [void]
        def insert_middleware_after(stack, base_options)
          inserted = middleware_insert_after_candidates.any? do |candidate|
            try_insert_after(stack, candidate, base_options)
          end

          # Only use as fallback if insertion after a specific middleware failed
          stack.use ::Verikloak::Middleware, **base_options unless inserted
        end

        # Attempt to insert after a candidate middleware.
        # Logs a warning and returns false when the candidate is not present.
        #
        # @param stack [ActionDispatch::MiddlewareStackProxy]
        # @param candidate [Object, nil]
        # @param base_options [Hash]
        # @return [Boolean]
        def try_insert_after(stack, candidate, base_options)
          return false unless candidate

          stack.insert_after candidate,
                             ::Verikloak::Middleware,
                             **base_options
          true
        rescue StandardError => e
          # Handle middleware insertion failures:
          # - Rails 8+: RuntimeError for missing middleware
          # - Earlier versions: ActionDispatch::MiddlewareStack::MiddlewareNotFound
          log_middleware_insertion_warning(candidate, e)
          false
        end

        # Build list of middleware to try as insertion points.
        # Starts with the configured value (if any) and falls back to defaults
        # that exist across supported Rails versions.
        #
        # @return [Array<Object>] ordered list of potential middleware targets
        def middleware_insert_after_candidates
          configured = Verikloak::Rails.config.middleware_insert_after

          defaults = []
          defaults << ::Rails::Rack::Logger if defined?(::Rails::Rack::Logger)
          defaults << ::ActionDispatch::Executor if defined?(::ActionDispatch::Executor)
          defaults << ::Rack::Head if defined?(::Rack::Head)
          defaults << ::Rack::Runtime if defined?(::Rack::Runtime)

          ([configured] + defaults).compact.uniq
        end

        # Log when a middleware insertion target cannot be found.
        #
        # @param candidate [Object] middleware we attempted to insert after
        # @param error [StandardError] the exception raised during insertion
        # @return [void]
        def log_middleware_insertion_warning(candidate, error)
          candidate_name = candidate.is_a?(Class) ? candidate.name : candidate.class.name
          message = "[verikloak] Unable to insert after #{candidate_name}: #{error.message}"
          RailtieLogger.warn(message)
        end
      end
    end
  end
end
