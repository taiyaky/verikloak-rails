# frozen_string_literal: true

require 'verikloak/rails/version'
require 'verikloak/rails/configuration'
require 'verikloak/rails/error_renderer'
require 'verikloak/rails/controller'
require 'verikloak/rails/railtie'

module Verikloak
  # Rails integration surface for Verikloak.
  #
  # Exposes configuration and Railtie hooks to wire middleware and controller
  # helpers into a Rails application.
  module Rails
    class << self
      # Global configuration object for verikloak-rails.
      #
      # @return [Verikloak::Rails::Configuration]
      # @example Read current leeway
      #   Verikloak::Rails.config.leeway #=> 60
      def config
        @config ||= Configuration.new
      end

      # Configure verikloak-rails.
      #
      # @yieldparam [Verikloak::Rails::Configuration] config
      # @return [void]
      # @example
      #   Verikloak::Rails.configure do |c|
      #     c.discovery_url = ENV['KEYCLOAK_DISCOVERY_URL']
      #     c.audience      = 'rails-api'
      #     c.leeway        = 30
      #   end
      def configure
        yield(config)
      end

      # Reset configuration to its default state.
      #
      # Primarily intended for test environments that need to ensure a clean
      # configuration between examples.
      #
      # @return [void]
      def reset!
        @config = nil
      end
    end
  end
end
