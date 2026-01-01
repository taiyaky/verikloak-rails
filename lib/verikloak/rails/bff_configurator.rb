# frozen_string_literal: true

module Verikloak
  module Rails
    # Handles BFF (Backend-for-Frontend) middleware configuration.
    # Extracted from Railtie to maintain class size limits.
    module BffConfigurator
      module_function

      # Insert the optional HeaderGuard middleware when verikloak-bff is present.
      # Skips insertion with a warning if trusted_proxies is not configured and
      # disabled is not explicitly set to true.
      #
      # @param stack [ActionDispatch::MiddlewareStackProxy]
      # @return [void]
      def configure_bff_guard(stack)
        return unless Verikloak::Rails.config.auto_insert_bff_header_guard
        return unless defined?(::Verikloak::BFF::HeaderGuard)

        unless configuration_valid?
          RailtieLogger.warn(
            '[verikloak] Skipping BFF::HeaderGuard insertion: trusted_proxies not configured. ' \
            'Set trusted_proxies in bff_header_guard_options to enable header validation.'
          )
          return
        end

        insert_header_guard(stack)
      end

      # Configure the verikloak-bff library when options are supplied.
      #
      # @return [void]
      def configure_library
        options = Verikloak::Rails.config.bff_header_guard_options
        return if options.nil? || (options.respond_to?(:empty?) && options.empty?)
        return unless defined?(::Verikloak::BFF) && ::Verikloak::BFF.respond_to?(:configure)

        apply_configuration(::Verikloak::BFF, options)
      rescue StandardError => e
        RailtieLogger.warn("[verikloak] Failed to apply BFF configuration: #{e.message}")
      end

      # Check if BFF configuration is valid for middleware insertion.
      # Returns true if:
      #   - disabled: true is set (HeaderGuard will be inserted but internally disabled), OR
      #   - trusted_proxies is configured with at least one entry
      #
      # @return [Boolean]
      def configuration_valid?
        return true unless defined?(::Verikloak::BFF)
        return true unless ::Verikloak::BFF.respond_to?(:config)

        bff_config = ::Verikloak::BFF.config

        # If disabled is explicitly set to true, allow insertion
        # (HeaderGuard will be inserted but internally disabled)
        return true if bff_config.respond_to?(:disabled) && bff_config.disabled

        # For legacy versions without trusted_proxies method, allow insertion
        return true unless bff_config.respond_to?(:trusted_proxies)

        # Require trusted_proxies to be a non-empty Array
        proxies = bff_config.trusted_proxies
        proxies.is_a?(Array) && !proxies.empty?
      end

      # Insert HeaderGuard middleware into the stack.
      #
      # @param stack [ActionDispatch::MiddlewareStackProxy]
      # @return [void]
      def insert_header_guard(stack)
        guard_before = Verikloak::Rails.config.bff_header_guard_insert_before
        guard_after = Verikloak::Rails.config.bff_header_guard_insert_after

        if guard_before
          stack.insert_before guard_before, ::Verikloak::BFF::HeaderGuard
        elsif guard_after
          stack.insert_after guard_after, ::Verikloak::BFF::HeaderGuard
        else
          stack.insert_before ::Verikloak::Middleware, ::Verikloak::BFF::HeaderGuard
        end
      end

      # Apply configuration options to the verikloak-bff namespace.
      # Supports hash-like and callable inputs.
      #
      # @param target [Module] Verikloak::BFF namespace
      # @param options [Hash, Proc, #to_h]
      # @return [void]
      def apply_configuration(target, options)
        if options.respond_to?(:call)
          target.configure(&options)
          return
        end

        hash = options.respond_to?(:to_h) ? options.to_h : options
        return unless hash.respond_to?(:each)

        entries = hash.transform_keys(&:to_sym)
        return if entries.empty?

        target.configure do |config|
          entries.each do |key, value|
            writer = "#{key}="
            config.public_send(writer, value) if config.respond_to?(writer)
          end
        end
      end
    end
  end
end
