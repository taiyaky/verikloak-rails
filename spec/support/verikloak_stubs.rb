# frozen_string_literal: true

# Shared stubs for verikloak base gem classes.
# These stubs allow testing verikloak-rails without requiring the actual verikloak gem.

module ::Verikloak; end unless defined?(::Verikloak)

# Stub for Verikloak::Error - the base error class used throughout verikloak
unless defined?(::Verikloak::Error)
  class ::Verikloak::Error < StandardError
    attr_reader :code

    def initialize(code = 'unauthorized', message = nil)
      @code = code
      super(message || code)
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
