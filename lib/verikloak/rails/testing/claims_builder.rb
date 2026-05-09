# frozen_string_literal: true

module Verikloak
  module Rails
    module Testing
      # Builds JWT-shaped claim Hashes from a user-like object for use in
      # tests. The returned Hash uses string keys to match what
      # `Verikloak::Middleware` writes to `env['verikloak.user']` after a
      # successful token verification.
      #
      # The user object is duck-typed: it must respond to `uid` and `email`.
      # Optional methods used when present:
      # - `username` or `preferred_username` (for `preferred_username`)
      # - `first_name` (for `given_name`)
      # - `last_name` (for `family_name`)
      module ClaimsBuilder
        # Build a baseline OIDC-style claim Hash.
        #
        # @param user [Object] user-like object responding to `uid`, `email`
        # @param groups [Array<String>] values for the `groups` claim
        # @param extra_claims [Hash] additional claims to merge in (overrides
        #   any keys produced from `user`/`groups`)
        # @return [Hash{String=>Object}]
        def build_jwt_claims(user, groups: [], extra_claims: {})
          base = {
            'sub' => user.uid,
            'email' => user.email,
            'preferred_username' => preferred_username_for(user),
            'given_name' => safe_call(user, :first_name),
            'family_name' => safe_call(user, :last_name),
            'groups' => groups,
            'realm_access' => { 'roles' => [] },
            'resource_access' => {},
            'aud' => ['account']
          }.compact

          base.merge(stringify_keys(extra_claims))
        end

        # Convenience wrapper that assigns the configured admin group.
        #
        # @param user [Object]
        # @param admin_group [String] group identifier (default: "/admin")
        # @param extra_claims [Hash]
        # @return [Hash{String=>Object}]
        def build_admin_claims(user, admin_group: '/admin', extra_claims: {})
          build_jwt_claims(user, groups: [admin_group], extra_claims: extra_claims)
        end

        # Convenience wrapper that assigns the configured user group.
        #
        # @param user [Object]
        # @param user_group [String] group identifier (default: "/user")
        # @param extra_claims [Hash]
        # @return [Hash{String=>Object}]
        def build_user_claims(user, user_group: '/user', extra_claims: {})
          build_jwt_claims(user, groups: [user_group], extra_claims: extra_claims)
        end

        private

        def preferred_username_for(user)
          return user.username           if user.respond_to?(:username)
          return user.preferred_username if user.respond_to?(:preferred_username)

          user.email
        end

        def safe_call(user, method)
          user.public_send(method) if user.respond_to?(method)
        end

        def stringify_keys(hash)
          return {} unless hash.is_a?(Hash)

          hash.transform_keys(&:to_s)
        end
      end
    end
  end
end
