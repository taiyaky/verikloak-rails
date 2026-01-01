# frozen_string_literal: true

# Minimal stub of the base Verikloak middleware for integration tests.
# It simulates successful authentication when a bearer token 'valid' is present.

# Load shared stubs for error classes
require_relative '../../support/verikloak_stubs'

module Verikloak
  class Middleware
    # Stub missing error classes
    class MiddlewareError < StandardError; end

    class << self
      attr_accessor :last_options
    end

    def initialize(app, **opts)
      @app = app
      self.class.last_options = opts
    end

    def call(env)
      # Record what the base middleware observed for Authorization header
      env['spec.base_middleware_seen_authorization'] = env['HTTP_AUTHORIZATION']
      if (auth = env['HTTP_AUTHORIZATION']).to_s.start_with?('Bearer')
        token = auth.split(' ', 2)[1]
        if token == 'valid'
          env['verikloak.token'] = token
          env['verikloak.user'] = { 'sub' => 'user-123', 'aud' => ['rails-api'] }
        end
      end
      @app.call(env)
    end
  end
end
