# frozen_string_literal: true

require 'spec_helper'
require 'verikloak/rails'

RSpec.describe Verikloak::Rails do
  # Reset configuration between tests
  before do
    described_class.instance_variable_set(:@config, nil)
  end

  describe '.config' do
    it 'returns a Configuration instance' do
      expect(described_class.config).to be_an_instance_of(Verikloak::Rails::Configuration)
    end

    it 'returns the same instance on subsequent calls (memoized)' do
      first_call = described_class.config
      second_call = described_class.config

      expect(first_call).to be(second_call)
    end

    it 'provides access to configuration attributes' do
      config = described_class.config

      expect(config).to respond_to(:discovery_url)
      expect(config).to respond_to(:audience)
      expect(config).to respond_to(:issuer)
      expect(config).to respond_to(:leeway)
      expect(config).to respond_to(:skip_paths)
      expect(config).to respond_to(:logger_tags)
      expect(config).to respond_to(:error_renderer)
      expect(config).to respond_to(:auto_include_controller)
      expect(config).to respond_to(:render_500_json)
      expect(config).to respond_to(:rescue_pundit)
    end

    it 'has sensible default values' do
      config = described_class.config

      expect(config.discovery_url).to be_nil
      expect(config.audience).to eq('rails-api')
      expect(config.leeway).to eq(60)
      expect(config.skip_paths).to eq(['/up', '/health', '/rails/health'])
      expect(config.auto_include_controller).to be true
      expect(config.render_500_json).to be false
      expect(config.rescue_pundit).to be true
    end
  end

  describe '.configure' do
    it 'yields the configuration object to the given block' do
      yielded_config = nil

      described_class.configure do |config|
        yielded_config = config
      end

      expect(yielded_config).to be(described_class.config)
    end

    it 'allows setting configuration values through the block' do
      described_class.configure do |config|
        config.discovery_url = 'https://auth.example.com/.well-known/openid-configuration'
        config.audience = 'test-api'
        config.leeway = 30
      end

      config = described_class.config
      expect(config.discovery_url).to eq('https://auth.example.com/.well-known/openid-configuration')
      expect(config.audience).to eq('test-api')
      expect(config.leeway).to eq(30)
    end

    it 'allows multiple configuration calls that accumulate changes' do
      described_class.configure do |config|
        config.discovery_url = 'https://auth.example.com/.well-known/openid-configuration'
        config.audience = 'first-api'
      end

      described_class.configure do |config|
        config.audience = 'second-api'
        config.leeway = 120
      end

      config = described_class.config
      expect(config.discovery_url).to eq('https://auth.example.com/.well-known/openid-configuration')
      expect(config.audience).to eq('second-api') # Updated value
      expect(config.leeway).to eq(120) # New value
    end

    it 'allows setting complex configuration values' do
      custom_renderer = double('CustomRenderer')
      custom_skip_paths = ['/metrics', '/status', '/health']
      custom_logger_tags = [:custom_tag, :request_id]

      described_class.configure do |config|
        config.audience = %w[api1 api2 api3]
        config.skip_paths = custom_skip_paths
        config.logger_tags = custom_logger_tags
        config.error_renderer = custom_renderer
        config.auto_include_controller = false
        config.render_500_json = true
        config.rescue_pundit = false
      end

      config = described_class.config
      expect(config.audience).to eq(%w[api1 api2 api3])
      expect(config.skip_paths).to eq(custom_skip_paths)
      expect(config.logger_tags).to eq(custom_logger_tags)
      expect(config.error_renderer).to eq(custom_renderer)
      expect(config.auto_include_controller).to be false
      expect(config.render_500_json).to be true
      expect(config.rescue_pundit).to be false
    end

    it 'returns the yielded block result' do
      result = described_class.configure do |config|
        config.audience = 'test-api'
        'block-result'
      end

      expect(result).to eq('block-result')
    end
  end

  describe 'module structure' do
    it 'defines the expected constants' do
      expect(described_class.const_defined?(:Configuration)).to be true
      expect(described_class.const_defined?(:ErrorRenderer)).to be true
      expect(described_class.const_defined?(:Controller)).to be true
      expect(described_class.const_defined?(:LazyMiddleware)).to be true
      expect(described_class.const_defined?(:Railtie)).to be true
    end

    it 'loads all required components' do
      expect(Verikloak::Rails::Configuration).to be < Object
      expect(Verikloak::Rails::ErrorRenderer).to be < Object
      expect(Verikloak::Rails::Controller).to be_a(Module)
      expect(Verikloak::Rails::LazyMiddleware).to be < Object
      expect(Verikloak::Rails::Railtie).to be < Rails::Railtie
    end
  end

  describe 'integration with Configuration class' do
    it 'provides access to middleware_options through config' do
      described_class.configure do |config|
        config.discovery_url = 'https://auth.example.com/.well-known/openid-configuration'
        config.audience = 'test-api'
        config.issuer = 'https://auth.example.com'
        config.leeway = 30
        config.skip_paths = ['/health']
      end

      options = described_class.config.middleware_options

      expect(options).to eq({
        discovery_url: 'https://auth.example.com/.well-known/openid-configuration',
        audience: 'test-api',
        issuer: 'https://auth.example.com',
        leeway: 30,
        skip_paths: ['/health']
      })
    end
  end
end