# frozen_string_literal: true

module Verikloak
  module Rails
    module Testing
      # Stubs the Verikloak middleware stack so authenticated request specs
      # can run without contacting an OIDC provider or signing real JWTs.
      #
      # `stub_verikloak_middleware` patches `#call` on the relevant
      # middlewares so they inject the supplied claims into
      # `env['verikloak.user']` and pass through to the next middleware.
      # The companion `verikloak.token` env key is also set when
      # available so controller helpers like `current_token` work.
      #
      # Requires RSpec-style mocks (`allow_any_instance_of`). Load
      # `verikloak/rails/testing/rspec` to wire things up automatically,
      # or include this module directly into your example groups.
      module MiddlewareStub
        DEFAULT_STUB_TOKEN = 'verikloak-test-token'

        # Stub all loaded Verikloak middlewares to populate the request
        # environment with the supplied claims.
        #
        # @param claims [Hash] value placed into `env['verikloak.user']`
        # @param token  [String] value placed into `env['verikloak.token']`
        # @return [void]
        def stub_verikloak_middleware(claims, token: DEFAULT_STUB_TOKEN)
          stub_core_middleware(claims, token)
          stub_bff_middleware(claims, token)           if bff_middleware_loaded?
          stub_audience_middleware(claims, token)      if audience_middleware_loaded?
        end

        private

        def stub_core_middleware(claims, token)
          return unless defined?(::Verikloak::Middleware)

          install_passthrough_stub(::Verikloak::Middleware, claims, token)
        end

        def stub_bff_middleware(claims, token)
          install_passthrough_stub(::Verikloak::BFF::HeaderGuard, claims, token)
        end

        def stub_audience_middleware(claims, token)
          install_passthrough_stub(::Verikloak::Audience::Middleware, claims, token)
        end

        def install_passthrough_stub(middleware_class, claims, token)
          allow_any_instance_of(middleware_class).to receive(:call) do |instance, env|
            env['verikloak.user']  = claims
            env['verikloak.token'] = token if token
            inner_app = instance.instance_variable_get(:@app)
            inner_app.call(env)
          end
        end

        def bff_middleware_loaded?
          defined?(::Verikloak::BFF::HeaderGuard)
        end

        def audience_middleware_loaded?
          defined?(::Verikloak::Audience::Middleware)
        end
      end
    end
  end
end
