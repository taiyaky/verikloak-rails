# frozen_string_literal: true

require 'spec_helper'
require 'generators/verikloak/install/install_generator'

RSpec.describe Verikloak::Generators::InstallGenerator do
  describe 'class definition' do
    it 'can be instantiated' do
      expect { described_class.new }.not_to raise_error
    end

    it 'has the correct description' do
      expect(described_class.desc).to include('Creates an initializer for verikloak-rails and documents basic usage.')
    end

    it 'has the correct source root' do
      expected_path = File.expand_path('templates', File.dirname(described_class.instance_method(:create_initializer).source_location[0]))
      expect(described_class.source_root).to eq(expected_path)
    end

    it 'inherits from Rails::Generators::Base' do
      expect(described_class.ancestors).to include(Rails::Generators::Base)
    end
  end

  describe 'instance methods' do
    let(:generator) { described_class.new }

    it 'responds to create_initializer method' do
      expect(generator).to respond_to(:create_initializer)
    end

    it 'responds to say_next_steps method' do
      expect(generator).to respond_to(:say_next_steps)
    end
  end

  describe 'template behavior' do
    it 'can read the template file' do
      template_path = File.join(described_class.source_root, 'initializer.rb.erb')
      expect(File.exist?(template_path)).to be true
      
      content = File.read(template_path)
      expect(content).to include('Rails.application.configure do')
      expect(content).to include('config.verikloak.discovery_url')
      expect(content).to include('config.verikloak.audience')
    end

    it 'template contains valid ERB syntax' do
      template_path = File.join(described_class.source_root, 'initializer.rb.erb')
      content = File.read(template_path)
      
      # Test that ERB can parse the template
      expect { ERB.new(content) }.not_to raise_error
    end

    it 'template produces valid Ruby when processed' do
      template_path = File.join(described_class.source_root, 'initializer.rb.erb')
      content = File.read(template_path)
      erb = ERB.new(content)
      processed = erb.result

      # Test that the processed template is valid Ruby
      expect { RubyVM::InstructionSequence.compile(processed) }.not_to raise_error
    end

    it 'template contains expected configuration options' do
      template_path = File.join(described_class.source_root, 'initializer.rb.erb')
      content = File.read(template_path)

      expect(content).to include("config.verikloak.discovery_url = ENV.fetch('KEYCLOAK_DISCOVERY_URL', nil)")
      expect(content).to include("config.verikloak.audience      = ENV.fetch('VERIKLOAK_AUDIENCE', 'rails-api')")
      expect(content).to include("config.verikloak.issuer        = ENV.fetch('VERIKLOAK_ISSUER', nil)")
      expect(content).to include("config.verikloak.leeway        = Integer(ENV.fetch('VERIKLOAK_LEEWAY', '60'))")
      expect(content).to include('config.verikloak.skip_paths    = %w[/up /health /rails/health]')
      expect(content).to include('config.verikloak.logger_tags = %i[request_id sub]')
      expect(content).to include('config.verikloak.auto_include_controller = true')
      expect(content).to include("config.verikloak.render_500_json = ENV.fetch('VERIKLOAK_RENDER_500', 'false') == 'true'")
      expect(content).to include("config.verikloak.rescue_pundit = ENV.fetch('VERIKLOAK_RESCUE_PUNDIT', 'true') == 'true'")
    end
  end
end