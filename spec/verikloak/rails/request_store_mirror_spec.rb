# frozen_string_literal: true

require 'spec_helper'
require_relative '../../support/verikloak_stubs'
require 'verikloak/rails'

RSpec.describe Verikloak::Rails::RequestStoreMirror do
  subject(:middleware) { described_class.new(inner_app) }

  let(:inner_app) { ->(_env) { [200, {}, ['ok']] } }

  before do
    Verikloak::Rails.reset!
  end

  after do
    Verikloak::Rails.reset!
  end

  context 'when RequestStore is available' do
    let(:store_class) do
      Class.new do
        class << self
          def store
            @store ||= {}
          end
        end
      end
    end

    before do
      stub_const('RequestStore', store_class)
    end

    it 'mirrors claims and token from the default env keys' do
      env = { 'verikloak.user' => { 'sub' => 'u-1' }, 'verikloak.token' => 't-1' }

      middleware.call(env)

      expect(RequestStore.store[:verikloak_user]).to eq('sub' => 'u-1')
      expect(RequestStore.store[:verikloak_token]).to eq('t-1')
    end

    it 'mirrors from custom env keys when configured' do
      Verikloak::Rails.config.user_env_key = 'custom.user'
      Verikloak::Rails.config.token_env_key = 'custom.token'
      env = { 'custom.user' => { 'sub' => 'u-2' }, 'custom.token' => 't-2' }

      middleware.call(env)

      expect(RequestStore.store[:verikloak_user]).to eq('sub' => 'u-2')
      expect(RequestStore.store[:verikloak_token]).to eq('t-2')
    end

    it 'overwrites stale values on unauthenticated requests' do
      RequestStore.store[:verikloak_user] = { 'sub' => 'stale' }
      RequestStore.store[:verikloak_token] = 'stale-token'

      middleware.call({})

      expect(RequestStore.store[:verikloak_user]).to be_nil
      expect(RequestStore.store[:verikloak_token]).to be_nil
    end

    it 'passes the env through to the inner app' do
      seen = nil
      app = lambda { |env|
        seen = env
        [204, {}, []]
      }
      env = { 'verikloak.user' => { 'sub' => 'u-1' } }

      status, = described_class.new(app).call(env)

      expect(status).to eq(204)
      expect(seen).to equal(env)
    end

    it 'never breaks the request when mirroring fails' do
      broken_store = Class.new do
        def self.store
          raise StandardError, 'store unavailable'
        end
      end
      stub_const('RequestStore', broken_store)

      status, = middleware.call({})

      expect(status).to eq(200)
    end
  end

  context 'when RequestStore is not defined' do
    it 'passes through untouched' do
      hide_const('RequestStore') if defined?(::RequestStore)

      status, _headers, body = middleware.call({})

      expect(status).to eq(200)
      expect(body).to eq(['ok'])
    end
  end
end
