# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'stringio'
require 'rails/generators'
require 'generators/verikloak/install/install_generator'

RSpec.describe Verikloak::Generators::InstallGenerator, type: :generator do
  let(:destination_root) { File.expand_path('../../tmp/generator_test', __dir__) }
  let(:initializer_path) { File.join(destination_root, 'config/initializers/verikloak.rb') }

  before do
    FileUtils.rm_rf(destination_root)
    FileUtils.mkdir_p(destination_root)
  end

  after do
    FileUtils.rm_rf(destination_root)
  end

  def run_generator(args = [], config = {})
    capture_output do
      described_class.start(args, config.merge(destination_root: destination_root))
    end
  end

  def capture_output
    stdout = StringIO.new
    original_stdout = $stdout
    $stdout = stdout
    yield
    stdout.string
  ensure
    $stdout = original_stdout
  end

  describe '#create_initializer' do
    it 'creates config/initializers/verikloak.rb with valid Ruby syntax' do
      run_generator

      expect(File.exist?(initializer_path)).to be true

      content = File.read(initializer_path)
      expect { RubyVM::InstructionSequence.compile(content) }.not_to raise_error
    end

    it 'generates initializer with all expected configuration options' do
      run_generator

      content = File.read(initializer_path)

      # Structure
      expect(content).to include('Rails.application.configure do')

      # Required settings
      expect(content).to include("config.verikloak.discovery_url = ENV.fetch('KEYCLOAK_DISCOVERY_URL', nil)")

      # Optional settings with defaults
      expect(content).to include("config.verikloak.audience = ENV.fetch('VERIKLOAK_AUDIENCE', 'rails-api')")
      expect(content).to include("config.verikloak.issuer = ENV.fetch('VERIKLOAK_ISSUER', nil)")
      expect(content).to include("config.verikloak.leeway = Integer(ENV.fetch('VERIKLOAK_LEEWAY', '60'))")
      expect(content).to include('config.verikloak.skip_paths = %w[/up /health /rails/health]')
      expect(content).to include('config.verikloak.logger_tags = %i[request_id sub]')

      # Boolean settings via ENV
      expect(content).to include("config.verikloak.auto_include_controller = ENV.fetch('VERIKLOAK_AUTO_INCLUDE', 'true') == 'true'")
      expect(content).to include("config.verikloak.render_500_json = ENV.fetch('VERIKLOAK_RENDER_500', 'false') == 'true'")

      # Commented optional setting
      expect(content).to include("# config.verikloak.rescue_pundit = ENV.fetch('VERIKLOAK_RESCUE_PUNDIT', 'true') == 'true'")
    end
  end

  describe '#say_next_steps' do
    it 'outputs completion message with setup instructions' do
      output = run_generator

      expect(output).to include('verikloak: initializer created')
      expect(output).to include('Next steps:')
      expect(output).to include('discovery_url')
      expect(output).to include('verikloak-bff')
      expect(output).to include('verikloak-pundit')
    end
  end
end
