# frozen_string_literal: true

require 'ipaddr'

module Verikloak
  module Rails
    # Internal namespace for Rack middleware glue.
    module MiddlewareIntegration
      # Promotes forwarded access tokens to Authorization when trusted.
      #
      # - Optionally trusts `X-Forwarded-Access-Token` from configured subnets
      # - Never overwrites an existing `Authorization` header
      # - Can derive the token from a prioritized list of headers
      class ForwardedAccessToken
        # Initialize the middleware.
        #
        # @param app [#call] next Rack app
        # @param trust_forwarded [Boolean] whether to trust forwarded access tokens
        # @param trusted_proxies [Array<IPAddr>, Array<String>] subnets considered trusted
        # @param header_priority [Array<String>] env header keys to search, in order
        def initialize(app, trust_forwarded:, trusted_proxies:,
                       header_priority: %w[HTTP_X_FORWARDED_ACCESS_TOKEN HTTP_AUTHORIZATION])
          @app = app
          @trust_forwarded = trust_forwarded
          @trusted_proxies = Array(trusted_proxies)
          @header_priority = header_priority
        end

        # Rack entry point: possibly promote a token and pass to the next app.
        #
        # @param env [Hash] Rack environment
        # @return [Array(Integer, Hash, #each)] Rack response triple from downstream app
        # @example Promote forwarded token
        #   env = { 'REMOTE_ADDR' => '10.0.0.1', 'HTTP_X_FORWARDED_ACCESS_TOKEN' => 'abc' }
        #   status, headers, body = middleware.call(env)
        def call(env)
          promote_forwarded_if_trusted(env)
          first = resolve_first_token_header(env)
          set_authorization_from(env, first) if first
          @app.call(env)
        end

        private

        # Promote X-Forwarded-Access-Token to Authorization when trusted.
        # @param env [Hash]
        # @return [void]
        def promote_forwarded_if_trusted(env)
          return unless @trust_forwarded && from_trusted_proxy?(env)

          forwarded = env['HTTP_X_FORWARDED_ACCESS_TOKEN']
          return if forwarded.to_s.empty?
          return unless env['HTTP_AUTHORIZATION'].to_s.empty?

          env['HTTP_AUTHORIZATION'] = ensure_bearer(forwarded)
        end

        # Resolve the first header key from which to source a bearer token.
        # Respects trust policy for forwarded tokens and never returns
        # 'HTTP_AUTHORIZATION'.
        #
        # @param env [Hash]
        # @return [String, nil]
        def resolve_first_token_header(env)
          candidates = @header_priority.dup
          candidates -= ['HTTP_X_FORWARDED_ACCESS_TOKEN'] unless @trust_forwarded && from_trusted_proxy?(env)
          candidates.find { |k| (val = env[k]) && !val.to_s.empty? && k != 'HTTP_AUTHORIZATION' }
        end

        # Set Authorization header from the given env header key.
        # @param env [Hash]
        # @param header_key [String]
        # @return [void]
        def set_authorization_from(env, header_key)
          token = env[header_key]
          env['HTTP_AUTHORIZATION'] ||= ensure_bearer(token)
        end

        # Normalize to a proper 'Bearer <token>' header value.
        # - Detects scheme case-insensitively
        # - Inserts a missing space (e.g., 'BearerXYZ' => 'Bearer XYZ')
        # - Collapses multiple spaces/tabs after the scheme to a single space
        # @param token [String]
        # @return [String]
        def ensure_bearer(token)
          s = token.to_s.strip
          # Case-insensitive 'Bearer' with spaces/tabs after
          if s =~ /\ABearer[ \t]+/i
            rest = s.sub(/\ABearer[ \t]+/i, '')
            return "Bearer #{rest}"
          end

          # Case-insensitive 'Bearer' with no separator (e.g., 'BearerXYZ')
          if s =~ /\ABearer(?![ \t])/i
            rest = s[6..] || ''
            return "Bearer #{rest}"
          end

          # No scheme present; add it
          "Bearer #{s}"
        end

        # Whether the request originates from a trusted proxy subnet.
        # @param env [Hash]
        # @return [Boolean]
        def from_trusted_proxy?(env)
          return true if @trusted_proxies.empty?

          # Prefer REMOTE_ADDR (direct peer). Fallback to the nearest proxy from X-Forwarded-For if present.
          ip = (env['REMOTE_ADDR'] || '').to_s.strip
          ip = env['HTTP_X_FORWARDED_FOR'].to_s.split(',').last.to_s.strip if ip.empty? && env['HTTP_X_FORWARDED_FOR']
          return false if ip.empty?

          begin
            req_ip = IPAddr.new(ip)
            @trusted_proxies.any? { |subnet| subnet.include?(req_ip) }
          rescue IPAddr::InvalidAddressError
            false
          end
        end
      end
    end
  end
end
