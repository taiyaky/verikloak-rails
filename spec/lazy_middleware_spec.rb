# frozen_string_literal: true

require 'spec_helper'
require 'verikloak/rails/lazy_middleware'

RSpec.describe Verikloak::Rails::LazyMiddleware do
  let(:app) { ->(_env) { [:ok, {}, ['success']] } }

  before do
    # Reset configuration between examples
    Verikloak::Rails.instance_variable_set(:@config, nil)
  end

  it 'raises a configuration error when discovery_url is missing' do
    stub_const('Verikloak::Error', Class.new(StandardError) do
      attr_reader :code

      def initialize(code = 'unauthorized', message = nil)
        @code = code
        super(message || code)
      end
    end)

    Verikloak::Rails.configure do |cfg|
      cfg.discovery_url = nil
      cfg.audience = 'rails-api'
    end

    lazy = described_class.new(app)

    expect { lazy.call({}) }
      .to raise_error do |error|
        expect(error.code.to_s).to eq('rails_configuration_missing')
        expect(error.message).to include('config.verikloak.discovery_url')
      end
  end

  it 'builds the underlying middleware only once' do
    constructed = []
    constructed_mutex = Mutex.new

    middleware_double = Class.new do
      define_method(:initialize) do |app, **options|
        constructed_mutex.synchronize { constructed << options }
        @app = app
      end

      define_method(:call) do |env|
        @app.call(env)
      end
    end

    stub_const('Verikloak::Middleware', middleware_double)

    Verikloak::Rails.configure do |cfg|
      cfg.discovery_url = 'https://auth.example.test/.well-known/openid-configuration'
      cfg.audience = 'rails-api'
    end

    lazy = described_class.new(app)
    2.times { lazy.call({}) }

    expect(constructed.size).to eq(1)
    expect(constructed.first[:discovery_url]).to eq('https://auth.example.test/.well-known/openid-configuration')
  end

  it 'is thread-safe when initializing the delegate' do
    constructed = []
    constructed_mutex = Mutex.new

    middleware_double = Class.new do
      define_method(:initialize) do |app, **options|
        constructed_mutex.synchronize { constructed << options }
        @app = app
      end

      define_method(:call) do |env|
        @app.call(env)
      end
    end

    stub_const('Verikloak::Middleware', middleware_double)

    Verikloak::Rails.configure do |cfg|
      cfg.discovery_url = 'https://auth.example.test/.well-known/openid-configuration'
      cfg.audience = 'rails-api'
    end

    lazy = described_class.new(app)

    threads = Array.new(5) { Thread.new { lazy.call({}) } }
    threads.each(&:value)

    expect(constructed.size).to eq(1)
  end
end
