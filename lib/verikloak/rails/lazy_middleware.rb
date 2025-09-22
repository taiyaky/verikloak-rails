# frozen_string_literal: true

module Verikloak
  module Rails
    # Lazily constructs the core middleware the first time it is needed so the
    # host application can boot generators/tasks before configuration is
    # complete. This keeps the "install generator runs on a fresh app" contract
    # intact while still failing fast when real traffic hits without the
    # required settings.
    #
    # The first request that hits this wrapper performs the actual
    # `Verikloak::Middleware` instantiation. Concurrent requests are serialized
    # via a mutex so only one delegate is built, avoiding duplicate network
    # discovery work in multi-threaded servers.
    class LazyMiddleware
      # Mapping of required configuration keys to human readable names used when
      # explaining what is missing from `config.verikloak`.
      CONFIG_KEYS = {
        discovery_url: 'config.verikloak.discovery_url'
      }.freeze

      # @param app [#call] downstream Rack application
      # @param options_resolver [#call, nil] callable that returns the options
      #   hash to pass to {::Verikloak::Middleware}. Defaults to the global Rails
      #   configuration.
      def initialize(app, options_resolver = nil)
        @app = app
        @options_resolver = options_resolver || DEFAULT_RESOLVER
        @delegate = nil
        @mutex = Mutex.new
      end

      # Rack entrypoint which ensures the delegate exists before forwarding
      # requests downstream.
      #
      # @param env [Hash] Rack environment
      # @return [Array(Integer, Hash, Array<String>)] standard Rack triple
      def call(env)
        ensure_delegate!
        @delegate.call(env)
      end

      private

      DEFAULT_RESOLVER = -> { Verikloak::Rails.config.middleware_options }.freeze
      private_constant :DEFAULT_RESOLVER

      # Lazily initialize the wrapped {::Verikloak::Middleware}, guarding with a
      # mutex so the delegate is constructed at most once across concurrent
      # threads.
      #
      # @return [void]
      def ensure_delegate!
        return if @delegate

        @mutex.synchronize do
          return if @delegate

          options = build_options
          @delegate = ::Verikloak::Middleware.new(@app, **options)
        end
      end

      # Resolve middleware options from the supplied resolver and ensure all
      # required keys are present before returning them.
      #
      # @return [Hash]
      # @raise [Verikloak::Error] when required configuration is missing
      def build_options
        options = @options_resolver.call
        raise configuration_error(CONFIG_KEYS.values) if options.nil?

        missing = missing_config(options)
        raise configuration_error(missing) if missing.any?

        options
      end

      # Determine which required configuration keys are missing from the
      # provided options hash.
      #
      # @param options [Hash]
      # @return [Array<String>] human-readable config paths that are absent
      def missing_config(options)
        CONFIG_KEYS.each_with_object([]) do |(key, label), list|
          value = options[key]
          next unless value.nil? || (value.respond_to?(:empty?) && value.empty?)

          list << label
        end
      end

      # Build an error describing which configuration entries are missing.
      # Falls back to a generic runtime error when the Verikloak error hierarchy
      # has not been loaded yet (e.g., during boots).
      #
      # @param missing [Array<String>] missing configuration labels
      # @return [Verikloak::Error, RuntimeError]
      def configuration_error(missing)
        message = "Verikloak configuration missing: #{missing.join(', ')}"
        if defined?(::Verikloak::Error)
          ::Verikloak::Error.new(message, code: 'rails_configuration_missing')
        else
          ::RuntimeError.new(message)
        end
      end
    end
  end
end
