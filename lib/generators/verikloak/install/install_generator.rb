# frozen_string_literal: true

require 'rails/generators'

module Verikloak
  module Generators
    # Rails generator that creates `config/initializers/verikloak.rb` and prints
    # follow-up instructions for configuring verikloak-rails.
    class InstallGenerator < ::Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      desc 'Creates an initializer for verikloak-rails and documents basic usage.'

      # Create the initializer file under config/initializers.
      # @return [void]
      # @example
      #   rails g verikloak:install
      def create_initializer
        template 'initializer.rb.erb', 'config/initializers/verikloak.rb'
      end

      # Print next steps for configuring the gem.
      # @return [void]
      def say_next_steps
        say <<~MSG
          ✅ verikloak: initializer created.

          Next steps:
          1) Ensure the base gem is installed:   gem 'verikloak', '>= 0.1.2', '< 0.2'
          2) Set discovery_url / audience in config/initializers/verikloak.rb
          3) (Optional) If you disable auto-include, add this line to ApplicationController:
               include Verikloak::Rails::Controller
        MSG
      end
    end
  end
end
