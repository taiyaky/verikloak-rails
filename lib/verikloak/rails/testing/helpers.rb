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
        # @param user [Object] application user
        # @param claims [Hash] JWT claims (string keys)
        # @return [Verikloak::Pundit::UserContext]
        # @raise [RuntimeError] if `verikloak-pundit` is not loaded
        def build_pundit_user_context(user, claims)
          unless defined?(::Verikloak::Pundit::UserContext)
            raise 'verikloak-pundit gem is not loaded; cannot build a UserContext'
          end

          ::Verikloak::Pundit::UserContext.new(user, claims)
        end

        # Convenience wrapper: admin claims + UserContext.
        #
        # @param user [Object]
        # @param admin_group [String]
        # @return [Verikloak::Pundit::UserContext]
        def build_admin_user_context(user, admin_group: '/admin')
          build_pundit_user_context(user, build_admin_claims(user, admin_group: admin_group))
        end

        # Convenience wrapper: user claims + UserContext.
        #
        # @param user [Object]
        # @param user_group [String]
        # @return [Verikloak::Pundit::UserContext]
        def build_user_user_context(user, user_group: '/user')
          build_pundit_user_context(user, build_user_claims(user, user_group: user_group))
        end
      end
    end
  end
end
