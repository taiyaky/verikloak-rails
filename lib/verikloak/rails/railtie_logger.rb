# frozen_string_literal: true

module Verikloak
  module Rails
    # Logging utilities for Railtie operations.
    # Provides consistent warning output across Rails versions.
    module RailtieLogger
      module_function

      # Log a warning using Rails.logger when available, otherwise fall back to Kernel#warn.
      # @param message [String]
      # @return [void]
      def warn(message)
        if (logger = rails_logger)
          logger.warn(message)
        else
          Kernel.warn(message)
        end
      end

      # Resolve the logger instance used for warnings, if present.
      # @return [Object, nil]
      def rails_logger
        return unless defined?(::Rails) && ::Rails.respond_to?(:logger)

        ::Rails.logger
      end
    end
  end
end
