# frozen_string_literal: true

require 'spec_helper'
require 'verikloak/rails/configuration'

RSpec.describe Verikloak::Rails::Configuration do
  let(:config) { described_class.new }

  describe '#initialize' do
    it 'sets sensible default values' do
      expect(config.discovery_url).to be_nil
      expect(config.audience).to eq('rails-api')
      expect(config.issuer).to be_nil
      expect(config.leeway).to eq(60)
      expect(config.skip_paths).to eq(['/up', '/health', '/rails/health'])
      expect(config.logger_tags).to eq(%i[request_id sub])
      expect(config.error_renderer).to be_an_instance_of(Verikloak::Rails::ErrorRenderer)
      expect(config.auto_include_controller).to be true
      expect(config.render_500_json).to be false
      expect(config.rescue_pundit).to be true
      expect(config.middleware_insert_before).to be_nil
      expect(config.middleware_insert_after).to be_nil
      expect(config.auto_insert_bff_header_guard).to be true
      expect(config.bff_header_guard_insert_before).to be_nil
      expect(config.bff_header_guard_insert_after).to be_nil
    end
  end

  describe 'attribute accessors' do
    it 'allows setting and getting discovery_url' do
      url = 'https://example.com/.well-known/openid-configuration'
      config.discovery_url = url
      expect(config.discovery_url).to eq(url)
    end

    it 'allows setting and getting audience as string' do
      config.audience = 'my-api'
      expect(config.audience).to eq('my-api')
    end

    it 'allows setting and getting audience as array' do
      config.audience = %w[api1 api2]
      expect(config.audience).to eq(%w[api1 api2])
    end

    it 'allows setting and getting issuer' do
      config.issuer = 'https://example.com'
      expect(config.issuer).to eq('https://example.com')
    end

    it 'allows setting and getting leeway' do
      config.leeway = 120
      expect(config.leeway).to eq(120)
    end

    it 'allows setting and getting skip_paths' do
      paths = ['/status', '/metrics']
      config.skip_paths = paths
      expect(config.skip_paths).to eq(paths)
    end

    it 'allows setting and getting logger_tags' do
      tags = [:custom_tag]
      config.logger_tags = tags
      expect(config.logger_tags).to eq(tags)
    end

    it 'allows setting and getting custom error_renderer' do
      custom_renderer = double('CustomRenderer')
      config.error_renderer = custom_renderer
      expect(config.error_renderer).to eq(custom_renderer)
    end

    it 'allows setting and getting boolean flags' do
      config.auto_include_controller = false
      expect(config.auto_include_controller).to be false

      config.render_500_json = true
      expect(config.render_500_json).to be true

      config.rescue_pundit = false
      expect(config.rescue_pundit).to be false

      config.auto_insert_bff_header_guard = false
      expect(config.auto_insert_bff_header_guard).to be false
    end

    it 'allows setting and getting middleware insertion options' do
      middleware_class = double('SomeMiddleware')
      
      config.middleware_insert_before = middleware_class
      expect(config.middleware_insert_before).to eq(middleware_class)

      config.middleware_insert_after = middleware_class
      expect(config.middleware_insert_after).to eq(middleware_class)

      config.bff_header_guard_insert_before = middleware_class
      expect(config.bff_header_guard_insert_before).to eq(middleware_class)

      config.bff_header_guard_insert_after = middleware_class
      expect(config.bff_header_guard_insert_after).to eq(middleware_class)
    end
  end

  describe '#middleware_options' do
    it 'returns a hash with core middleware options' do
      config.discovery_url = 'https://auth.example.com/.well-known/openid-configuration'
      config.audience = 'test-api'
      config.issuer = 'https://auth.example.com'
      config.leeway = 30
      config.skip_paths = ['/health']

      options = config.middleware_options

      expect(options).to eq({
        discovery_url: 'https://auth.example.com/.well-known/openid-configuration',
        audience: 'test-api',
        issuer: 'https://auth.example.com',
        leeway: 30,
        skip_paths: ['/health']
      })
    end

    it 'includes nil values in the options hash' do
      config.discovery_url = nil
      config.audience = nil
      config.issuer = nil

      options = config.middleware_options

      expect(options).to include(
        discovery_url: nil,
        audience: nil,
        issuer: nil
      )
    end

    it 'returns options with array audience' do
      config.audience = %w[api1 api2]

      options = config.middleware_options

      expect(options[:audience]).to eq(%w[api1 api2])
    end

    it 'does not include Rails-specific configuration in middleware options' do
      config.auto_include_controller = false
      config.render_500_json = true
      config.rescue_pundit = false

      options = config.middleware_options

      expect(options).not_to have_key(:auto_include_controller)
      expect(options).not_to have_key(:render_500_json)
      expect(options).not_to have_key(:rescue_pundit)
      expect(options).not_to have_key(:error_renderer)
      expect(options).not_to have_key(:logger_tags)
    end
  end
end