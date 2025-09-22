# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

require 'active_support/tagged_logging'

# Ensure the stubbed base middleware is found before the Railtie requires it.
$LOAD_PATH.unshift File.expand_path('../stubs', __dir__)

require 'rails'
require 'action_controller/railtie'
require 'rack/test'

# Define Verikloak::Error for controller rescue behavior if not present.
module ::Verikloak; end unless defined?(::Verikloak)
unless defined?(::Verikloak::Error)
  class ::Verikloak::Error < StandardError
    attr_reader :code
    def initialize(code = 'unauthorized', message = nil)
      @code = code
      super(message || code)
    end
  end
end

# Define a minimal Pundit::NotAuthorizedError to exercise the rescue path
module ::Pundit; end unless defined?(::Pundit)
unless defined?(::Pundit::NotAuthorizedError)
  class ::Pundit::NotAuthorizedError < StandardError; end
end

# Define a minimal BFF header guard to exercise auto-insertion behavior.
module ::Verikloak; end unless defined?(::Verikloak)
module ::Verikloak::Bff; end unless defined?(::Verikloak::Bff)
unless defined?(::Verikloak::Bff::HeaderGuard)
  class ::Verikloak::Bff::HeaderGuard
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

  it 'includes controller concern and authenticates when Authorization is valid' do
    get '/hello', {}, { 'HTTP_AUTHORIZATION' => 'Bearer valid' }
    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)['sub']).to eq('user-123')
  end

  it 'returns 401 JSON when unauthenticated' do
    get '/hello'
    expect(last_response.status).to eq(401)
    body = JSON.parse(last_response.body)
    expect(body['error']).to eq('unauthorized')
  end

  # BFF header handling moved to verikloak-bff; not covered here

  it 'propagates configured options to base middleware' do
    # Ensure middleware stack is built at least once
    get '/hello'
    opts = ::Verikloak::Middleware.last_options
    expect(opts[:discovery_url]).to eq('https://example/.well-known/openid-configuration')
    expect(opts[:audience]).to eq('rails-api')
    expect(opts[:leeway]).to eq(60)
    expect(opts[:skip_paths]).to include('/up')
  end

  it 'promotes forwarded tokens via the auto-inserted header guard' do
    get '/hello', {}, { 'HTTP_X_FORWARDED_ACCESS_TOKEN' => 'valid' }
    expect(last_response.status).to eq(200)
    expect(last_request.env['spec.header_guard_invoked']).to eq(true)
    expect(last_request.env['spec.base_middleware_seen_authorization']).to eq('Bearer valid')
  end

  it 'does not override Authorization when header guard runs' do
    get '/hello', {}, { 'HTTP_AUTHORIZATION' => 'Bearer valid', 'HTTP_X_FORWARDED_ACCESS_TOKEN' => 'malicious' }
    expect(last_response.status).to eq(200)
    expect(last_request.env['spec.base_middleware_seen_authorization']).to eq('Bearer valid')
  end

  it 'enforces audience via with_required_audience! (success)' do
    get '/aud_ok', {}, { 'HTTP_AUTHORIZATION' => 'Bearer valid' }
    expect(last_response.status).to eq(200)
  end

  it 'enforces audience via with_required_audience! (forbidden)' do
    get '/aud_ng', {}, { 'HTTP_AUTHORIZATION' => 'Bearer valid' }
    expect(last_response.status).to eq(403)
    body = JSON.parse(last_response.body)
    expect(body['error']).to eq('forbidden')
  end

  it 'renders 500 JSON when render_500_json is enabled and StandardError occurs' do
    io = StringIO.new
    tagged_logger = ActiveSupport::TaggedLogging.new(Logger.new(io))

    previous = Rails.logger
    Rails.logger = tagged_logger
    begin
      get '/boom', {}, { 'HTTP_AUTHORIZATION' => 'Bearer valid' }
    ensure
      Rails.logger = previous
    end
    expect(last_response.status).to eq(500)
    body = JSON.parse(last_response.body)
    expect(body['error']).to eq('internal_server_error')
    io.rewind
    expect(io.string).to include('StandardError', 'boom')
  end

  it 'rescues Pundit::NotAuthorizedError to 403 JSON' do
    get '/pundit', {}, { 'HTTP_AUTHORIZATION' => 'Bearer valid' }
    expect(last_response.status).to eq(403)
    body = JSON.parse(last_response.body)
    expect(body['error']).to eq('forbidden')
  end

  # Note: Disabling Pundit rescue must be configured before Rails boots.
  # Runtime toggling is not asserted here because the concern is auto-included
  # into ActionController::Base at boot and rescue handlers are inherited.

  it 'tags logs with request_id and sub when available' do
    # Stub a logger that captures tags
    captured = []
    stub = Class.new do
      def initialize(captured) = @captured = captured
      # minimal logger API used by Rails::Rack::Logger
      %i[debug info warn error fatal unknown].each { |m| define_method(m) { |_msg = nil| } }
      def level=(val); @level = val; end
      def tagged(*tags)
        @captured << tags
        yield
      end
    end.new(captured)

    previous = Rails.logger
    app # ensure initialized before swapping logger
    Rails.logger = stub
    begin
      allow_any_instance_of(HelloController).to receive(:current_subject).and_return("user-123\nmalicious\tvalue")
      get '/hello', {}, { 'HTTP_AUTHORIZATION' => 'Bearer valid', 'HTTP_X_REQUEST_ID' => 'req-xyz' }
    ensure
      Rails.logger = previous
    end
    expect(captured).not_to be_empty
    expect(captured.flatten).to include('req:req-xyz', 'sub:user-123 malicious value')
  end

  context 'when discovery_url is missing' do
    it 'skips middleware insertion and logs a helpful warning' do
      Verikloak::Rails.reset!
      ::Verikloak::Middleware.last_options = nil

      log_io = StringIO.new
      logger = Logger.new(log_io)

      previous_app = Rails.application
      previous_logger = Rails.logger

      app_class = Class.new(::Rails::Application)
      app_class.config.root = File.expand_path('../..', __dir__)
      app_class.config.secret_key_base = 'missing-discovery-secret'
      app_class.config.eager_load = false
      app_class.config.consider_all_requests_local = true
      app_class.config.hosts.clear if app_class.config.respond_to?(:hosts)
      app_class.config.logger = logger
      app_class.config.verikloak.discovery_url = nil
      app_class.config.verikloak.auto_insert_bff_header_guard = true

      begin
        # Rails freezes the default middleware operations after the first
        # application boots. Ensure this throwaway app receives a writable copy
        # so the boot sequence can mutate the stack without raising FrozenError.
        middleware_proxy = app_class.config.middleware
        if middleware_proxy.respond_to?(:dup)
          duplicated = middleware_proxy.dup
          ops_var = %i[@operations @middlewares].find do |ivar|
            duplicated.instance_variable_defined?(ivar)
          end
          if ops_var
            operations = duplicated.instance_variable_get(ops_var)
            duplicated.instance_variable_set(ops_var, operations.dup) if operations.respond_to?(:dup)
          end
          app_class.config.middleware = duplicated
        end

        Rails.application = app_class if Rails.respond_to?(:application=)
        Rails.logger = logger if Rails.respond_to?(:logger=)

        app_class.initialize!

        middlewares = app_class.middleware.middlewares
        expect(middlewares).not_to include(::Verikloak::Middleware)
        expect(middlewares).not_to include(::Verikloak::Bff::HeaderGuard)
        expect(::Verikloak::Middleware.last_options).to be_nil

        log_io.rewind
        expect(log_io.string).to include('discovery_url is not configured')
      ensure
        Rails.application = previous_app if Rails.respond_to?(:application=)
        Rails.logger = previous_logger if Rails.respond_to?(:logger=)
      end
    end
  end
end
