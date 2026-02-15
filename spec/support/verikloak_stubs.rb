# frozen_string_literal: true

# Shared stubs for verikloak base gem classes.
# These stubs allow testing verikloak-rails without requiring the actual verikloak gem.

module ::Verikloak; end unless defined?(::Verikloak)

# Stub for Verikloak::Error - the base error class used throughout verikloak.
# Matches the core gem's current signature: Error.new(message, code:, http_status:)
unless defined?(::Verikloak::Error)
  class ::Verikloak::Error < StandardError
    attr_reader :code, :http_status

    def initialize(message = nil, code: nil, http_status: nil)
      super(message)
      @code = code
      @http_status = http_status
    end
  end
end

# Stub for Verikloak::DiscoveryError - raised when OIDC discovery fails
unless defined?(::Verikloak::DiscoveryError)
  class ::Verikloak::DiscoveryError < ::Verikloak::Error; end
end

# Stub for Pundit::NotAuthorizedError - used for Pundit integration tests
module ::Pundit; end unless defined?(::Pundit)
unless defined?(::Pundit::NotAuthorizedError)
  class ::Pundit::NotAuthorizedError < StandardError; end
end
