# frozen_string_literal: true

require 'rails/railtie'
require 'verikloak/middleware'

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
      # @return [void]
      initializer 'verikloak.controller' do |_app|
        ActiveSupport.on_load(:action_controller_base) do
          include Verikloak::Rails::Controller if Verikloak::Rails.config.auto_include_controller
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
          configure_bff_library

          unless discovery_url_present?
            log_missing_discovery_url_warning
            return
          end

          stack = insert_base_middleware(app)
          configure_bff_guard(stack) if stack

          stack
        end

        # Insert the optional HeaderGuard middleware when verikloak-bff is present.
        #
        # @param stack [ActionDispatch::MiddlewareStackProxy]
        # @return [void]
        def configure_bff_guard(stack)
          return unless Verikloak::Rails.config.auto_insert_bff_header_guard
          return unless defined?(::Verikloak::Bff::HeaderGuard)

          guard_before = Verikloak::Rails.config.bff_header_guard_insert_before
          guard_after = Verikloak::Rails.config.bff_header_guard_insert_after
          if guard_before
            stack.insert_before guard_before, ::Verikloak::Bff::HeaderGuard
          elsif guard_after
            stack.insert_after guard_after, ::Verikloak::Bff::HeaderGuard
          else
            stack.insert_before ::Verikloak::Middleware, ::Verikloak::Bff::HeaderGuard
          end
        end

        # Apply configuration options to the verikloak-bff namespace.
        # Supports hash-like and callable inputs.
        #
        # @param target [Module] Verikloak::BFF or Verikloak::Bff namespace
        # @param options [Hash, Proc, #to_h]
        # @return [void]
        def apply_bff_configuration(target, options)
          if options.respond_to?(:call)
            target.configure(&options)
            return
          end

          hash = options.respond_to?(:to_h) ? options.to_h : options
          return unless hash.respond_to?(:each)

          entries = hash.transform_keys(&:to_sym)

          return if entries.empty?

          target.configure do |config|
            entries.each do |key, value|
              writer = "#{key}="
              config.public_send(writer, value) if config.respond_to?(writer)
            end
          end
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

        # Configure the verikloak-bff library when options are supplied.
        #
        # @return [void]
        def configure_bff_library
          options = Verikloak::Rails.config.bff_header_guard_options
          return if options.nil? || (options.respond_to?(:empty?) && options.empty?)

          target = if defined?(::Verikloak::BFF) && ::Verikloak::BFF.respond_to?(:configure)
                     ::Verikloak::BFF
                   elsif defined?(::Verikloak::Bff) && ::Verikloak::Bff.respond_to?(:configure)
                     ::Verikloak::Bff
                   end

          return unless target

          apply_bff_configuration(target, options)
        rescue StandardError => e
          warn_with_fallback("[verikloak] Failed to apply BFF configuration: #{e.message}")
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
          warn_with_fallback(message)
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
          warn_with_fallback(message)
        end

        # Resolve the logger instance used for warnings, if present.
        # @return [Object, nil]
        def rails_logger
          return unless defined?(::Rails) && ::Rails.respond_to?(:logger)

          ::Rails.logger
        end

        # Log a warning using Rails.logger when available, otherwise fall back to Kernel#warn.
        # @param message [String]
        # @return [void]
        def warn_with_fallback(message)
          if (logger = rails_logger)
            logger.warn(message)
          else
            warn(message)
          end
        end
      end
    end
  end
end
