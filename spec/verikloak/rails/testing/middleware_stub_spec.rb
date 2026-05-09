# frozen_string_literal: true

require 'spec_helper'
require 'verikloak/rails/testing/middleware_stub'

RSpec.describe Verikloak::Rails::Testing::MiddlewareStub do
  include Verikloak::Rails::Testing::MiddlewareStub

  let(:claims) { { 'sub' => 'user-123', 'aud' => ['rails-api'] } }

  before do
    stub_const('Verikloak::Middleware', Class.new do
      def initialize(app, **_opts) = (@app = app)
      def call(_env)
        raise 'real verikloak middleware should not run in this test'
      end
    end)
  end

  it 'replaces Verikloak::Middleware#call with a passthrough that injects claims' do
    inner_app = ->(env) { [200, {}, [env['verikloak.user']]] }
    middleware = Verikloak::Middleware.new(inner_app)

    stub_verikloak_middleware(claims)

    env = { 'PATH_INFO' => '/' }
    status, _headers, body = middleware.call(env)

    expect(status).to eq(200)
    expect(env['verikloak.user']).to eq(claims)
    expect(env['verikloak.token']).to eq(described_class::DEFAULT_STUB_TOKEN)
    expect(body.first).to eq(claims)
  end

  it 'allows overriding the injected token' do
    inner_app = ->(_env) { [204, {}, []] }
    middleware = Verikloak::Middleware.new(inner_app)

    stub_verikloak_middleware(claims, token: 'custom-token')

    env = {}
    middleware.call(env)
    expect(env['verikloak.token']).to eq('custom-token')
  end

  it 'also stubs Verikloak::BFF::HeaderGuard when loaded' do
    bff_class = Class.new do
      def initialize(app) = (@app = app)
      def call(_env)
        raise 'real BFF middleware should not run'
      end
    end
    stub_const('Verikloak::BFF', Module.new)
    stub_const('Verikloak::BFF::HeaderGuard', bff_class)

    inner_app = ->(_env) { [204, {}, []] }
    middleware = bff_class.new(inner_app)

    stub_verikloak_middleware(claims)

    env = {}
    middleware.call(env)
    expect(env['verikloak.user']).to eq(claims)
  end

  it 'also stubs Verikloak::Audience::Middleware when loaded' do
    aud_class = Class.new do
      def initialize(app) = (@app = app)
      def call(_env)
        raise 'real Audience middleware should not run'
      end
    end
    stub_const('Verikloak::Audience', Module.new)
    stub_const('Verikloak::Audience::Middleware', aud_class)

    inner_app = ->(_env) { [204, {}, []] }
    middleware = aud_class.new(inner_app)

    stub_verikloak_middleware(claims)

    env = {}
    middleware.call(env)
    expect(env['verikloak.user']).to eq(claims)
  end
end
