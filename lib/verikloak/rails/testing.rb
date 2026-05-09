# frozen_string_literal: true

module Verikloak
  module Rails
    # Test-support helpers for application specs that exercise endpoints
    # protected by Verikloak.
    #
    # Submodules:
    # - {ClaimsBuilder}  – build JWT-shaped Hashes from a user-like
    #   object. Pure Ruby, no test-framework dependency, so it can be
    #   used standalone (e.g. from `Minitest`).
    # - {MiddlewareStub} – stub Verikloak/BFF/Audience middleware to
    #   inject pre-built claims into `env['verikloak.user']`. Requires
    #   RSpec mocks (`allow_any_instance_of`); not usable from
    #   `Minitest` without bringing in `rspec-mocks`.
    # - {Helpers}        – mixes in {ClaimsBuilder} and {MiddlewareStub}
    #   and adds Pundit `UserContext` builders when `verikloak-pundit`
    #   is loaded.
    #
    # The simplest way to wire these into an RSpec suite is to require
    # `verikloak/rails/testing/rspec` from `spec/rails_helper.rb`.
    module Testing
      autoload :ClaimsBuilder,  'verikloak/rails/testing/claims_builder'
      autoload :MiddlewareStub, 'verikloak/rails/testing/middleware_stub'
      autoload :Helpers,        'verikloak/rails/testing/helpers'
    end
  end
end
