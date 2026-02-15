# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

require 'active_support/tagged_logging'

# Ensure the stubbed base middleware is found before the Railtie requires it.
$LOAD_PATH.unshift File.expand_path('../stubs', __dir__)

# Load shared stubs for error classes
require_relative '../support/verikloak_stubs'

require 'rails'
require 'action_controller/railtie'
require 'rack/test'

# Stub the Discovery class that the real middleware expects
unless defined?(::Verikloak::Middleware::Discovery)
  module ::Verikloak
    class Middleware
      class Discovery
        def initialize(*); end
        def call(*); end
      end
    end
  end
end

# Define a minimal BFF header guard to exercise auto-insertion behavior.
module ::Verikloak::BFF; end unless defined?(::Verikloak::BFF)
unless defined?(::Verikloak::BFF::HeaderGuard)
  class ::Verikloak::BFF::HeaderGuard
    class << self
      attr_accessor :last_env
    end

    def initialize(app)
      @app = app
    end

    def call(env)
      env['spec.header_guard_invoked'] = true
      forwarded = env['HTTP_X_FORWARDED_ACCESS_TOKEN'].to_s.strip
      if env['HTTP_AUTHORIZATION'].to_s.empty? && !forwarded.empty?
        env['HTTP_AUTHORIZATION'] = "Bearer #{forwarded}"
      end
      self.class.last_env = env
      @app.call(env)
    end
  end
end

require 'verikloak/rails'

class HelloController < ActionController::Base
  protect_from_forgery with: :null_session

  def index
    render json: { sub: (respond_to?(:current_subject) ? current_subject : nil) }
  end

  def aud_ok
    with_required_audience!('rails-api')
    render json: { ok: true }
  end

  def aud_ng
    with_required_audience!('missing-aud')
    render json: { ok: true }
  end

  def boom
    raise StandardError, 'boom'
  end

  def pundit
    raise ::Pundit::NotAuthorizedError, 'nope'
  end
end

class TestApp < Rails::Application
  config.root = File.expand_path('../..', __dir__)
  config.secret_key_base = 'test-secret-key'
  config.eager_load = false
  config.consider_all_requests_local = true
  # Opt in to Rails 8.1 behavior to avoid deprecation around `to_time`
  config.active_support.to_time_preserves_timezone = :zone
  # Clear allowed hosts for testing
  config.hosts.clear if config.respond_to?(:hosts)
  config.logger = Logger.new(nil)

  # verikloak-rails configuration
  config.verikloak.discovery_url = 'https://example/.well-known/openid-configuration'
  config.verikloak.audience = 'rails-api'
  config.verikloak.leeway = 60
  config.verikloak.render_500_json = true

  routes.append do
    get '/hello', to: 'hello#index'
    get '/aud_ok', to: 'hello#aud_ok'
    get '/aud_ng', to: 'hello#aud_ng'
    get '/boom', to: 'hello#boom'
    get '/pundit', to: 'hello#pundit'
  end
end

RSpec.describe 'Rails integration', type: :request do
  include Rack::Test::Methods

  before do
    Verikloak::Rails.reset!
  end

  def app
    @app ||= begin
      TestApp.initialize! unless TestApp.initialized?
      # Ensure a usable logger in case Rails.logger is nil in this environment
      ::Rails.logger ||= Logger.new($stderr)
      Rails.application
    end
  end

  # Note: Most integration tests are temporarily skipped due to complex middleware dependencies
  # The core functionality is tested in unit tests and the Pundit integration spec

  # ── E2E HTTP tests ───────────────────────────────────────────────
  # These tests exercise the full Rack middleware pipeline through
  # actual HTTP requests via Rack::Test, using the stub middleware
  # in spec/stubs/verikloak/middleware.rb.

  context 'E2E: authenticated request' do
    it 'returns 200 with claims when a valid Bearer token is provided' do
      header 'Authorization', 'Bearer valid'
      get '/hello'
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body['sub']).to eq('user-123')
    end
  end

  context 'E2E: unauthenticated request' do
    it 'returns 401 when no token is provided (authenticate_user! is auto-included)' do
      get '/hello'
      expect(last_response.status).to eq(401)
      body = JSON.parse(last_response.body)
      expect(body['error']).to eq('unauthorized')
    end
  end

  context 'E2E: audience enforcement' do
    it 'returns 200 when audience check passes' do
      header 'Authorization', 'Bearer valid'
      get '/aud_ok'
      expect(last_response.status).to eq(200)
    end

    it 'returns 403 JSON when audience check fails' do
      header 'Authorization', 'Bearer valid'
      get '/aud_ng'
      expect(last_response.status).to eq(403)
      body = JSON.parse(last_response.body)
      expect(body).to have_key('error')
    end
  end

  context 'E2E: unhandled exception' do
    it 'returns 500 JSON when render_500_json is enabled' do
      header 'Authorization', 'Bearer valid'
      get '/boom'
      expect(last_response.status).to eq(500)
      body = JSON.parse(last_response.body)
      expect(body['error']).to eq('internal_server_error')
    end
  end

  context 'E2E: Pundit authorization failure' do
    it 'returns 403 JSON for Pundit::NotAuthorizedError' do
      header 'Authorization', 'Bearer valid'
      get '/pundit'
      expect(last_response.status).to eq(403)
      body = JSON.parse(last_response.body)
      expect(body['error']).to eq('forbidden')
    end
  end

  context 'when discovery_url is missing' do
    it 'handles missing discovery_url configuration gracefully' do
      # Reset state for this test
      Verikloak::Rails.reset!
      if ::Verikloak::Middleware.respond_to?(:last_options=)
        ::Verikloak::Middleware.last_options = nil
      end

      # Configure with missing discovery_url
      Verikloak::Rails.configure do |config|
        config.discovery_url = nil
        config.audience = 'test-audience'
      end
      
      # Verify that the configuration reflects the missing discovery_url
      expect(Verikloak::Rails.config.discovery_url).to be_nil
      expect(Verikloak::Rails.config.audience).to eq('test-audience')
      
      # Test that middleware_options includes the nil discovery_url
      options = Verikloak::Rails.config.middleware_options
      expect(options[:discovery_url]).to be_nil
      expect(options[:audience]).to eq('test-audience')
      
      # Verify no middleware was actually configured with these options
      if ::Verikloak::Middleware.respond_to?(:last_options)
        expect(::Verikloak::Middleware.last_options).to be_nil
      end
    end
  end

  context 'when advanced middleware options are configured' do
    it 'forwards options to the base middleware' do
      Verikloak::Rails.configure do |config|
        config.discovery_url = 'https://example/.well-known/openid-configuration'
        config.audience = 'rails-api'
        config.token_verify_options = { verify_iat: false }
        config.decoder_cache_limit = 8
        config.token_env_key = 'custom.token'
        config.user_env_key = 'custom.user'
      end

      options = Verikloak::Rails.config.middleware_options
      expect(options[:token_verify_options]).to eq(verify_iat: false)
      expect(options[:decoder_cache_limit]).to eq(8)
      expect(options[:token_env_key]).to eq('custom.token')
      expect(options[:user_env_key]).to eq('custom.user')
    end
  end

  context 'when issuer parameter is configured' do
    it 'forwards issuer to middleware_options when configured' do
      Verikloak::Rails.configure do |config|
        config.discovery_url = 'https://example/.well-known/openid-configuration'
        config.audience = 'rails-api'
        config.issuer = 'https://custom-issuer.example.com'
      end

      options = Verikloak::Rails.config.middleware_options
      expect(options[:issuer]).to eq('https://custom-issuer.example.com')
    end

    it 'does not include issuer in middleware_options when not configured' do
      Verikloak::Rails.configure do |config|
        config.discovery_url = 'https://example/.well-known/openid-configuration'
        config.audience = 'rails-api'
        config.issuer = nil
      end

      options = Verikloak::Rails.config.middleware_options
      # middleware_options uses .compact, so nil values are excluded
      expect(options).not_to have_key(:issuer)
    end
  end

  context 'when bff_header_guard_options are provided' do
    let(:rails_cfg) do
      require 'active_support/ordered_options'
      ActiveSupport::OrderedOptions.new
    end

    let(:stack) do
      instance_double('MiddlewareStack').tap do |middleware|
        allow(middleware).to receive(:insert_before)
        allow(middleware).to receive(:insert_after)
        allow(middleware).to receive(:use)
      end
    end

    let(:app_config) do
      instance_double('RailsConfig', verikloak: rails_cfg)
    end

    let(:app) do
      instance_double('RailsApp', config: app_config, middleware: stack)
    end

    before do
      rails_cfg.discovery_url = 'https://example/.well-known/openid-configuration'
      rails_cfg.audience = 'rails-api'
      rails_cfg.bff_header_guard_options = { trusted_proxies: ['127.0.0.1'], prefer_forwarded: false }

      stub_const('::Verikloak::BFF::HeaderGuard', Class.new)

      bff_config_class = Class.new do
        attr_accessor :trusted_proxies, :prefer_forwarded

        def initialize
          @trusted_proxies = []
          @prefer_forwarded = true
        end

        def dup
          copy = self.class.new
          copy.trusted_proxies = @trusted_proxies.dup
          copy.prefer_forwarded = @prefer_forwarded
          copy
        end
      end

      bff_config = bff_config_class.new

      # Ensure ::Verikloak::BFF is properly configured for the test
      unless ::Verikloak::BFF.respond_to?(:configure)
        ::Verikloak::BFF.singleton_class.class_eval do
          define_method(:configure) do |&block|
            block.call(bff_config) if block
            bff_config
          end

          define_method(:config) do
            bff_config
          end
        end
      end
    end

    it 'bridges configuration into verikloak-bff' do
      ::Verikloak::Rails::Railtie.send(:configure_middleware, app)

      config = ::Verikloak::BFF.config
      expect(config.trusted_proxies).to eq(['127.0.0.1'])
      expect(config.prefer_forwarded).to be(false)
    end
  end
end
