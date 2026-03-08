# frozen_string_literal: true

require 'verikloak/skip_path_matcher'

module Verikloak
  module Rails
    # Wraps {Verikloak::SkipPathMatcher} into a standalone object so the
    # controller layer can reuse the same skip-path logic as the Rack middleware.
    #
    # @example
    #   checker = SkipPathChecker.new(['/health', '/public/*'])
    #   checker.skip?('/health')    #=> true
    #   checker.skip?('/api/users') #=> false
    class SkipPathChecker
      include Verikloak::SkipPathMatcher

      # @param paths [Array<String, Regexp>] skip-path patterns
      def initialize(paths)
        compile_skip_paths(Array(paths))
      end

      public :skip?
    end
  end
end
