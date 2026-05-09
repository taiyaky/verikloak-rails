# frozen_string_literal: true

module Verikloak
  module Rails
    # Test-support helpers for application specs that exercise endpoints
    # protected by Verikloak.
    #
    # The submodules here are deliberately decoupled from any specific test
    # framework so they can be used standalone (e.g., from `Minitest`) or
    # plugged into RSpec via `require "verikloak/rails/testing/rspec"`.
    #
    # Submodules:
    # - {ClaimsBuilder}  – build JWT-shaped Hashes from a user-like object
    # - {MiddlewareStub} – stub Verikloak/BFF/Audience middleware to inject
    #   pre-built claims into `env['verikloak.user']`
    # - {Helpers}        – mixes in {ClaimsBuilder} and {MiddlewareStub} and
    #   adds Pundit `UserContext` builders when `verikloak-pundit` is loaded
    module Testing
      autoload :ClaimsBuilder,  'verikloak/rails/testing/claims_builder'
      autoload :MiddlewareStub, 'verikloak/rails/testing/middleware_stub'
      autoload :Helpers,        'verikloak/rails/testing/helpers'
    end
  end
end
