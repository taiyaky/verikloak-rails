# frozen_string_literal: true

require 'set'

module Verikloak
  module Rails
    module Controller
      # Rescue handlers and 500-error logging backing the Controller
      # concern's `rescue_from` registrations. Turns uncaught exceptions
      # into the standardized JSON responses while keeping the underlying
      # failure visible to operators through the innermost logger.
      module ErrorHandling
        private

        # Handle uncaught StandardError: render the generic JSON 500 when
        # `render_500_json` is enabled, otherwise re-raise so Rails' default
        # error handling applies. The handler is only registered when the flag
        # is enabled at include time; this request-time check additionally lets
        # a runtime opt-out take effect.
        #
        # @param exception [StandardError]
        # @return [void]
        # @raise [StandardError] the original exception when rendering is disabled
        def _verikloak_handle_standard_error(exception)
          raise exception unless Verikloak::Rails.config.render_500_json

          _verikloak_render_internal_error(exception)
        end

        # Handle `Pundit::NotAuthorizedError`: render 403 JSON when
        # `rescue_pundit` is enabled; otherwise fall through to the generic
        # StandardError handling (500 JSON or re-raise).
        #
        # @param exception [StandardError]
        # @return [void]
        # @raise [StandardError] the original exception when both rescues are disabled
        def _verikloak_handle_pundit_error(exception)
          if Verikloak::Rails.config.rescue_pundit
            render json: { error: 'forbidden', message: exception.message }, status: :forbidden
          else
            _verikloak_handle_standard_error(exception)
          end
        end

        # Log the exception and render the static JSON 500 body.
        #
        # @param exception [Exception]
        # @return [void]
        def _verikloak_render_internal_error(exception)
          _verikloak_log_internal_error(exception)
          render json: { error: 'internal_server_error', message: 'An unexpected error occurred' },
                 status: :internal_server_error
        end

        # Write StandardError details to the controller or Rails logger when
        # rendering the generic 500 JSON response. Logging ensures the
        # underlying failure is still visible to operators even though the
        # response body is static.
        #
        # @param exception [Exception]
        # @return [void]
        def _verikloak_log_internal_error(exception)
          target_logger = _verikloak_base_logger
          return unless target_logger.respond_to?(:error)

          target_logger.error("[Verikloak] #{exception.class}: #{exception.message}")
          backtrace = exception.backtrace
          target_logger.error(backtrace.join("\n")) if backtrace&.any?
        rescue StandardError
          # Never allow logging failures to interfere with request handling.
          nil
        end

        # Locate the innermost logger that responds to `error`.
        # @return [Object, nil]
        def _verikloak_base_logger
          root_logger = if defined?(::Rails) && ::Rails.respond_to?(:logger)
                          ::Rails.logger
                        elsif respond_to?(:logger)
                          logger
                        end
          current = root_logger
          seen = Set.new
          while current.respond_to?(:logger)
            break unless seen.add?(current.object_id)

            next_logger = current.logger
            break if next_logger.nil? || next_logger.equal?(current)

            current = next_logger
          end
          current
        end
      end
    end
  end
end
