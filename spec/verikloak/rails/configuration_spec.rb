# frozen_string_literal: true

require 'spec_helper'
require_relative '../../support/verikloak_stubs'
require 'verikloak/rails'

RSpec.describe Verikloak::Rails::Configuration do
  subject(:config) { described_class.new }

  describe '#effective_token_env_key and #effective_user_env_key' do
    it 'returns the core middleware defaults when no custom keys are configured' do
      expect(config.effective_token_env_key).to eq('verikloak.token')
      expect(config.effective_user_env_key).to eq('verikloak.user')
    end

    it 'returns the configured custom keys' do
      config.token_env_key = 'custom.token'
      config.user_env_key = 'custom.user'

      expect(config.effective_token_env_key).to eq('custom.token')
      expect(config.effective_user_env_key).to eq('custom.user')
    end

    it 'falls back to the defaults when the configured keys are blank' do
      config.token_env_key = ''
      config.user_env_key = '   '

      expect(config.effective_token_env_key).to eq('verikloak.token')
      expect(config.effective_user_env_key).to eq('verikloak.user')
    end

    it 'strips surrounding whitespace to match the key the core middleware writes' do
      config.token_env_key = "custom.token\n"
      config.user_env_key = ' custom.user '

      expect(config.effective_token_env_key).to eq('custom.token')
      expect(config.effective_user_env_key).to eq('custom.user')
    end
  end

  describe '#jwks_refresh_interval' do
    it 'defaults to nil and is omitted from middleware_options so the core default applies' do
      expect(config.jwks_refresh_interval).to be_nil
      expect(config.middleware_options).not_to have_key(:jwks_refresh_interval)
    end

    it 'is forwarded through middleware_options when set' do
      config.jwks_refresh_interval = 120

      expect(config.middleware_options[:jwks_refresh_interval]).to eq(120)
    end

    it 'forwards 0 (revalidate on every request) instead of compacting it away' do
      config.jwks_refresh_interval = 0

      expect(config.middleware_options[:jwks_refresh_interval]).to eq(0)
    end
  end
end
