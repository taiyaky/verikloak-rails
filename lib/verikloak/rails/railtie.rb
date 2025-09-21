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
      config.verikloak = ActiveSupport::OrderedOptions.new

      # Apply configuration and insert middleware.
      # @return [void]
      initializer 'verikloak.configure' do |app|
        stack = ::Verikloak::Rails::Railtie.send(:configure_middleware, app)
        ::Verikloak::Rails::Railtie.send(:configure_bff_guard, stack)
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
          base_options = Verikloak::Rails.config.middleware_options
          stack = app.middleware
          if (before = Verikloak::Rails.config.middleware_insert_before)
            stack.insert_before before,
                                ::Verikloak::Middleware,
                                **base_options
          else
            after = Verikloak::Rails.config.middleware_insert_after || ::Rails::Rack::Logger
            if after
              stack.insert_after after,
                                 ::Verikloak::Middleware,
                                 **base_options
            else
              stack.use ::Verikloak::Middleware, **base_options
            end
          end
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

        # Sync configuration from the Rails application into Verikloak::Rails.
        #
        # @param app [Rails::Application]
        # @return [void]
        def apply_configuration(app)
          Verikloak::Rails.configure do |c|
            rails_cfg = app.config.verikloak
            %i[discovery_url audience issuer leeway skip_paths
               logger_tags error_renderer auto_include_controller
               render_500_json rescue_pundit middleware_insert_before
               middleware_insert_after auto_insert_bff_header_guard
               bff_header_guard_insert_before bff_header_guard_insert_after].each do |key|
              c.send("#{key}=", rails_cfg[key]) if rails_cfg.key?(key)
            end
            c.rescue_pundit = false if !rails_cfg.key?(:rescue_pundit) && defined?(::Verikloak::Pundit)
          end
        end
      end
    end
  end
end
