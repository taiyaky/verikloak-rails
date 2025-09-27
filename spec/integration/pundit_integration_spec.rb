# frozen_string_literal: true

require 'spec_helper'
require 'verikloak/rails'

RSpec.describe 'Pundit integration auto-disable behavior' do
  CONFIG_KEYS = Verikloak::Rails::Railtie::CONFIG_KEYS
  before do
    Verikloak::Rails.reset!
  end

  context 'when verikloak-pundit is loaded' do
    before do
      # Mock the verikloak-pundit gem being loaded
      stub_const('::Verikloak::Pundit', Module.new)
    end

    it 'auto-disables rescue_pundit when not explicitly configured' do
      # Simulate Rails configuration without rescue_pundit key
      require 'active_support/ordered_options'
      rails_cfg = ActiveSupport::OrderedOptions.new
      rails_cfg.discovery_url = 'https://example/.well-known/openid-configuration'
      rails_cfg.audience = 'test-audience'
      # Note: rescue_pundit key is intentionally not set

      Verikloak::Rails.configure do |c|
        CONFIG_KEYS.each do |key|
          c.send("#{key}=", rails_cfg[key]) if rails_cfg.key?(key)
        end
        # This is the key logic from the Railtie
        c.rescue_pundit = false if !rails_cfg.key?(:rescue_pundit) && defined?(::Verikloak::Pundit)
      end

      expect(Verikloak::Rails.config.rescue_pundit).to eq(false)
    end

    it 'respects explicit rescue_pundit configuration' do
      # Simulate Rails configuration with explicit rescue_pundit setting
      require 'active_support/ordered_options'
      rails_cfg = ActiveSupport::OrderedOptions.new
      rails_cfg.discovery_url = 'https://example/.well-known/openid-configuration'
      rails_cfg.audience = 'test-audience'
      rails_cfg.rescue_pundit = true  # Explicitly set

      Verikloak::Rails.configure do |c|
        CONFIG_KEYS.each do |key|
          c.send("#{key}=", rails_cfg[key]) if rails_cfg.key?(key)
        end
        # Should NOT auto-disable because rescue_pundit was explicitly set
        c.rescue_pundit = false if !rails_cfg.key?(:rescue_pundit) && defined?(::Verikloak::Pundit)
      end

      expect(Verikloak::Rails.config.rescue_pundit).to eq(true)
    end
  end

  context 'when verikloak-pundit is not loaded' do
    it 'defaults rescue_pundit to true' do
      Verikloak::Rails.configure do |config|
        config.discovery_url = 'https://example/.well-known/openid-configuration'
        config.audience = 'test-audience'
      end

      expect(Verikloak::Rails.config.rescue_pundit).to eq(true)
    end

    it 'keeps rescue_pundit true when not explicitly configured' do
      # Simulate Rails configuration without rescue_pundit key
      require 'active_support/ordered_options'
      rails_cfg = ActiveSupport::OrderedOptions.new
      rails_cfg.discovery_url = 'https://example/.well-known/openid-configuration'
      rails_cfg.audience = 'test-audience'

      Verikloak::Rails.configure do |c|
        CONFIG_KEYS.each do |key|
          c.send("#{key}=", rails_cfg[key]) if rails_cfg.key?(key)
        end
        # Should NOT auto-disable because verikloak-pundit is not present
        c.rescue_pundit = false if !rails_cfg.key?(:rescue_pundit) && defined?(::Verikloak::Pundit)
      end

      expect(Verikloak::Rails.config.rescue_pundit).to eq(true)
    end
  end
end
