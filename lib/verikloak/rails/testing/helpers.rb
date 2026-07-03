# frozen_string_literal: true

require 'verikloak/rails/testing/claims_builder'
require 'verikloak/rails/testing/middleware_stub'

module Verikloak
  module Rails
    module Testing
      # Top-level mix-in for RSpec example groups (request and policy specs).
      # Composes {ClaimsBuilder} and {MiddlewareStub}, and adds
      # `Verikloak::Pundit::UserContext` builders when the optional
      # `verikloak-pundit` gem is loaded.
      module Helpers
        include ClaimsBuilder
        include MiddlewareStub

        # Build a `Verikloak::Pundit::UserContext` for policy specs.
        #
        # Matches verikloak-pundit's constructor
        # (`UserContext.new(claims, resource_client: nil, config: nil)`),
        # which wraps the JWT claims only — the application user object is
        # not part of the context.
        #
        # @param claims [Hash] JWT claims (string keys)
        # @param options [Hash] keyword options forwarded to `UserContext.new`
        #   (e.g. `resource_client:`, `config:`)
        # @return [Verikloak::Pundit::UserContext]
        # @raise [RuntimeError] if `verikloak-pundit` is not loaded
        def build_pundit_user_context(claims, **options)
          unless defined?(::Verikloak::Pundit::UserContext)
            raise 'verikloak-pundit gem is not loaded; cannot build a UserContext'
          end

          ::Verikloak::Pundit::UserContext.new(claims, **options)
        end

        # Convenience wrapper: admin claims + UserContext.
        #
        # @param user [Object] user-like object used to build the claims
        # @param admin_group [String]
        # @param options [Hash] forwarded to {#build_pundit_user_context}
        # @return [Verikloak::Pundit::UserContext]
        def build_admin_user_context(user, admin_group: '/admin', **options)
          build_pundit_user_context(build_admin_claims(user, admin_group: admin_group), **options)
        end

        # Convenience wrapper: user claims + UserContext.
        #
        # @param user [Object] user-like object used to build the claims
        # @param user_group [String]
        # @param options [Hash] forwarded to {#build_pundit_user_context}
        # @return [Verikloak::Pundit::UserContext]
        def build_user_user_context(user, user_group: '/user', **options)
          build_pundit_user_context(build_user_claims(user, user_group: user_group), **options)
        end
      end
    end
  end
end
