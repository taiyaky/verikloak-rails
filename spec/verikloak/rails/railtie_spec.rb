# frozen_string_literal: true

require 'spec_helper'
require 'rails'
require 'action_dispatch'
require 'active_support/ordered_options'
require 'verikloak/rails'

RSpec.describe Verikloak::Rails::Railtie do
  let(:app) do
    Class.new(Rails::Application) do
      config.eager_load = false
      config.secret_key_base = 'test-secret'
      config.consider_all_requests_local = true
      config.logger = Logger.new(nil)
      config.verikloak = ActiveSupport::OrderedOptions.new
    end
  end

  # Simple mock that tracks method calls without complex middleware stack behavior
  let(:middleware_stack) do
    double('middleware_stack').tap do |stack|
      allow(stack).to receive(:insert_after)
      allow(stack).to receive(:insert_before)
      allow(stack).to receive(:use)
    end
  end

  before do
    # Reset Rails configuration between tests
    Verikloak::Rails.instance_variable_set(:@config, nil)
    allow(app).to receive(:middleware).and_return(middleware_stack)
  end

  describe 'verikloak.configure initializer' do
    it 'applies configuration from Rails config' do
      app.config.verikloak.discovery_url = 'https://test.example.com/.well-known/openid-configuration'
      app.config.verikloak.audience = 'test-api'
      app.config.verikloak.leeway = 30

      # Trigger the initializer
      described_class.send(:configure_middleware, app)

      expect(Verikloak::Rails.config.discovery_url).to eq('https://test.example.com/.well-known/openid-configuration')
      expect(Verikloak::Rails.config.audience).to eq('test-api')
      expect(Verikloak::Rails.config.leeway).to eq(30)
    end

    it 'inserts LazyMiddleware into the middleware stack by default' do
      expect(middleware_stack).to receive(:insert_after)
        .with(Rails::Rack::Logger, Verikloak::Rails::LazyMiddleware, kind_of(Proc))

      described_class.send(:configure_middleware, app)
    end

    it 'inserts middleware before specified middleware when configured' do
      app.config.verikloak.middleware_insert_before = ActionDispatch::RequestId

      expect(middleware_stack).to receive(:insert_before)
        .with(ActionDispatch::RequestId, Verikloak::Rails::LazyMiddleware, kind_of(Proc))

      described_class.send(:configure_middleware, app)
    end

    it 'inserts middleware after specified middleware when configured' do
      app.config.verikloak.middleware_insert_after = ActionDispatch::RequestId

      expect(middleware_stack).to receive(:insert_after)
        .with(ActionDispatch::RequestId, Verikloak::Rails::LazyMiddleware, kind_of(Proc))

      described_class.send(:configure_middleware, app)
    end

    it 'normalizes Verikloak::Middleware to LazyMiddleware in configuration' do
      stub_const('::Verikloak::Middleware', Class.new)
      app.config.verikloak.middleware_insert_before = ::Verikloak::Middleware

      expect(middleware_stack).to receive(:insert_before)
        .with(Verikloak::Rails::LazyMiddleware, Verikloak::Rails::LazyMiddleware, kind_of(Proc))

      described_class.send(:configure_middleware, app)
    end
  end

  describe 'BFF header guard configuration' do
    before do
      # Define the BFF module and HeaderGuard for these tests
      stub_const('::Verikloak::Bff', Module.new)
      stub_const('::Verikloak::Bff::HeaderGuard', Class.new)
      # Reset configuration to ensure clean state
      Verikloak::Rails.configure do |c|
        c.auto_insert_bff_header_guard = true
      end
    end

    it 'inserts BFF HeaderGuard before LazyMiddleware by default' do
      expect(middleware_stack).to receive(:insert_before)
        .with(Verikloak::Rails::LazyMiddleware, ::Verikloak::Bff::HeaderGuard)

      described_class.send(:configure_bff_guard, middleware_stack)
    end

    it 'inserts BFF HeaderGuard before specified middleware when configured' do
      Verikloak::Rails.configure do |c|
        c.bff_header_guard_insert_before = ActionDispatch::RequestId
      end

      expect(middleware_stack).to receive(:insert_before)
        .with(ActionDispatch::RequestId, ::Verikloak::Bff::HeaderGuard)

      described_class.send(:configure_bff_guard, middleware_stack)
    end

    it 'inserts BFF HeaderGuard after specified middleware when configured' do
      Verikloak::Rails.configure do |c|
        c.bff_header_guard_insert_after = Rails::Rack::Logger
        c.bff_header_guard_insert_before = nil
      end

      expect(middleware_stack).to receive(:insert_after)
        .with(Rails::Rack::Logger, ::Verikloak::Bff::HeaderGuard)

      described_class.send(:configure_bff_guard, middleware_stack)
    end

    it 'does not insert BFF HeaderGuard when auto_insert_bff_header_guard is false' do
      Verikloak::Rails.configure do |c|
        c.auto_insert_bff_header_guard = false
      end

      expect(middleware_stack).not_to receive(:insert_before)
      expect(middleware_stack).not_to receive(:insert_after)

      described_class.send(:configure_bff_guard, middleware_stack)
    end

    it 'does not insert BFF HeaderGuard when Verikloak::Bff::HeaderGuard is not defined' do
      hide_const('::Verikloak::Bff::HeaderGuard')

      expect(middleware_stack).not_to receive(:insert_before)
      expect(middleware_stack).not_to receive(:insert_after)

      described_class.send(:configure_bff_guard, middleware_stack)
    end
  end

  describe 'configuration application' do
    it 'applies all supported configuration options' do
      app.config.verikloak.discovery_url = 'https://auth.example.com/.well-known/openid-configuration'
      app.config.verikloak.audience = %w[api1 api2]
      app.config.verikloak.issuer = 'https://auth.example.com'
      app.config.verikloak.leeway = 120
      app.config.verikloak.skip_paths = ['/status']
      app.config.verikloak.logger_tags = [:request_id]
      app.config.verikloak.auto_include_controller = false
      app.config.verikloak.render_500_json = true
      app.config.verikloak.rescue_pundit = false

      described_class.send(:apply_configuration, app)

      config = Verikloak::Rails.config
      expect(config.discovery_url).to eq('https://auth.example.com/.well-known/openid-configuration')
      expect(config.audience).to eq(%w[api1 api2])
      expect(config.issuer).to eq('https://auth.example.com')
      expect(config.leeway).to eq(120)
      expect(config.skip_paths).to eq(['/status'])
      expect(config.logger_tags).to eq([:request_id])
      expect(config.auto_include_controller).to be false
      expect(config.render_500_json).to be true
      expect(config.rescue_pundit).to be false
    end

    it 'does not override config values that are not set in Rails config' do
      # Set some custom values in Verikloak::Rails config
      Verikloak::Rails.configure do |c|
        c.leeway = 90
        c.audience = 'custom-api'
      end

      # Only set discovery_url in Rails config
      app.config.verikloak.discovery_url = 'https://auth.example.com/.well-known/openid-configuration'

      described_class.send(:apply_configuration, app)

      config = Verikloak::Rails.config
      expect(config.discovery_url).to eq('https://auth.example.com/.well-known/openid-configuration')
      expect(config.leeway).to eq(90) # Should not be overridden
      expect(config.audience).to eq('custom-api') # Should not be overridden
    end

    it 'sets rescue_pundit to false when Verikloak::Pundit is defined' do
      stub_const('::Verikloak::Pundit', Module.new)

      described_class.send(:apply_configuration, app)

      expect(Verikloak::Rails.config.rescue_pundit).to be false
    end

    it 'keeps rescue_pundit as true when Verikloak::Pundit is not defined' do
      described_class.send(:apply_configuration, app)

      expect(Verikloak::Rails.config.rescue_pundit).to be true
    end

    it 'allows explicit rescue_pundit configuration to override Pundit detection' do
      stub_const('::Verikloak::Pundit', Module.new)
      app.config.verikloak.rescue_pundit = true

      described_class.send(:apply_configuration, app)

      expect(Verikloak::Rails.config.rescue_pundit).to be true
    end
  end

  describe '.normalize_middleware_target' do
    it 'returns nil for nil input' do
      result = described_class.send(:normalize_middleware_target, nil)
      expect(result).to be_nil
    end

    it 'converts Verikloak::Middleware to LazyMiddleware' do
      stub_const('::Verikloak::Middleware', Class.new)
      result = described_class.send(:normalize_middleware_target, ::Verikloak::Middleware)
      expect(result).to eq(Verikloak::Rails::LazyMiddleware)
    end

    it 'returns other middleware classes unchanged' do
      result = described_class.send(:normalize_middleware_target, ActionDispatch::RequestId)
      expect(result).to eq(ActionDispatch::RequestId)
    end

    it 'returns string middleware names unchanged' do
      result = described_class.send(:normalize_middleware_target, 'Rails::Rack::Logger')
      expect(result).to eq('Rails::Rack::Logger')
    end
  end
end