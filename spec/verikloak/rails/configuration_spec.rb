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
end
