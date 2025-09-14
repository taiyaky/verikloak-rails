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
        Verikloak::Rails.configure do |c|
          rails_cfg = app.config.verikloak
          %i[discovery_url audience issuer leeway skip_paths
             logger_tags error_renderer auto_include_controller
             render_500_json rescue_pundit].each do |key|
            c.send("#{key}=", rails_cfg[key]) if rails_cfg.key?(key)
          end
        end
        app.middleware.insert_after ::Rails::Rack::Logger,
                                    ::Verikloak::Middleware,
                                    **Verikloak::Rails.config.middleware_options
      end

      # Optionally include the controller concern when ActionController loads.
      # @return [void]
      initializer 'verikloak.controller' do |_app|
        ActiveSupport.on_load(:action_controller_base) do
          include Verikloak::Rails::Controller if Verikloak::Rails.config.auto_include_controller
        end
      end
    end
  end
end
