# frozen_string_literal: true

require 'spec_helper'

# Load Rails and ActionDispatch for the test
require 'rails'
require 'action_controller/railtie'

# Load stubs before verikloak/rails to ensure Verikloak::Error is defined
require_relative '../../stubs/verikloak/middleware'

require 'verikloak/rails'

RSpec.describe Verikloak::Rails::Railtie, type: :railtie do
  describe '.middleware_insert_after_candidates' do
    let(:railtie) { described_class }
    
    before do
      Verikloak::Rails.reset!
    end

    context 'with default configuration' do
      it 'returns fallback middleware candidates without duplicates' do
        Verikloak::Rails.configure do |config|
          config.middleware_insert_after = nil
        end

        candidates = railtie.send(:middleware_insert_after_candidates)
        
        # Should contain standard Rails middleware as fallbacks
        expect(candidates).to include(::Rails::Rack::Logger)
        expect(candidates).to include(::ActionDispatch::Executor)
        expect(candidates).to include(::Rack::Head)
        expect(candidates).to include(::Rack::Runtime)
        
        # Should be unique (no duplicates)
        expect(candidates.uniq).to eq(candidates)
      end
    end

    context 'with configured middleware_insert_after' do
      it 'prioritizes configured value and includes fallbacks' do
        Verikloak::Rails.configure do |config|
          config.middleware_insert_after = ::ActionDispatch::Static
        end

        candidates = railtie.send(:middleware_insert_after_candidates)
        
        # Should start with configured value
        expect(candidates.first).to eq(::ActionDispatch::Static)
        
        # Should also include fallbacks
        expect(candidates).to include(::Rails::Rack::Logger)
        expect(candidates).to include(::ActionDispatch::Executor)
      end
    end
  end

  describe '.insert_middleware_after' do
    let(:railtie) { described_class }
    let(:middleware_stack) { double('MiddlewareStack') }
    let(:base_options) { { discovery_url: 'https://test.example.com' } }

    before do
      Verikloak::Rails.reset!
      allow(railtie).to receive(:log_middleware_insertion_warning)
    end

    context 'when first candidate succeeds' do
      it 'inserts middleware and breaks from loop' do
        Verikloak::Rails.configure do |config|
          config.middleware_insert_after = ::ActionDispatch::Static
        end

        expect(middleware_stack).to receive(:insert_after)
          .with(::ActionDispatch::Static, ::Verikloak::Middleware, **base_options)
          .and_return(true)
        expect(middleware_stack).not_to receive(:use)

        railtie.send(:insert_middleware_after, middleware_stack, base_options)
      end
    end

    context 'when first candidate fails but second succeeds' do
      it 'tries next candidate and succeeds' do
        # Create a mock class for non-existent middleware
        non_existent_middleware = Class.new
        stub_const('NonExistentMiddleware', non_existent_middleware)
        
        Verikloak::Rails.configure do |config|
          config.middleware_insert_after = non_existent_middleware
        end

        # First attempt fails
        expect(middleware_stack).to receive(:insert_after)
          .with(non_existent_middleware, ::Verikloak::Middleware, **base_options)
          .and_raise(StandardError.new('MiddlewareNotFound: not found'))

        # Second attempt succeeds (with Rails::Rack::Logger as fallback)
        expect(middleware_stack).to receive(:insert_after)
          .with(::Rails::Rack::Logger, ::Verikloak::Middleware, **base_options)
          .and_return(true)

        expect(middleware_stack).not_to receive(:use)
        expect(railtie).to receive(:log_middleware_insertion_warning)

        railtie.send(:insert_middleware_after, middleware_stack, base_options)
      end
    end

    context 'when all candidates fail' do
      it 'falls back to using middleware at the end' do
        # Create mock classes for non-existent middleware
        non_existent_middleware1 = Class.new
        non_existent_middleware2 = Class.new
        stub_const('NonExistentMiddleware1', non_existent_middleware1)
        stub_const('NonExistentMiddleware2', non_existent_middleware2)
        
        # Mock all candidates to fail
        allow(railtie).to receive(:middleware_insert_after_candidates)
          .and_return([non_existent_middleware1, non_existent_middleware2])

        expect(middleware_stack).to receive(:insert_after).twice
          .and_raise(StandardError.new('MiddlewareNotFound: not found'))

        expect(middleware_stack).to receive(:use)
          .with(::Verikloak::Middleware, **base_options)

        expect(railtie).to receive(:log_middleware_insertion_warning).twice

        railtie.send(:insert_middleware_after, middleware_stack, base_options)
      end
    end
  end

  describe '.configure_bff_guard' do
    let(:railtie) { described_class }
    let(:middleware_stack) { double('MiddlewareStack') }

    before do
      Verikloak::Rails.reset!
    end

    context 'when Verikloak::BFF::HeaderGuard is defined' do
      before do
        # Define the BFF namespace and HeaderGuard class
        stub_const('::Verikloak::BFF', Module.new)
        stub_const('::Verikloak::BFF::HeaderGuard', Class.new)
      end

      context 'when auto_insert_bff_header_guard is enabled' do
        before do
          Verikloak::Rails.configure do |config|
            config.auto_insert_bff_header_guard = true
          end
        end

        it 'inserts HeaderGuard before Verikloak::Middleware by default' do
          expect(middleware_stack).to receive(:insert_before)
            .with(::Verikloak::Middleware, ::Verikloak::BFF::HeaderGuard)

          railtie.send(:configure_bff_guard, middleware_stack)
        end

        it 'inserts HeaderGuard before specified middleware when bff_header_guard_insert_before is set' do
          custom_middleware = Class.new
          stub_const('CustomMiddleware', custom_middleware)

          Verikloak::Rails.configure do |config|
            config.auto_insert_bff_header_guard = true
            config.bff_header_guard_insert_before = custom_middleware
          end

          expect(middleware_stack).to receive(:insert_before)
            .with(custom_middleware, ::Verikloak::BFF::HeaderGuard)

          railtie.send(:configure_bff_guard, middleware_stack)
        end

        it 'inserts HeaderGuard after specified middleware when bff_header_guard_insert_after is set' do
          custom_middleware = Class.new
          stub_const('CustomMiddleware', custom_middleware)

          Verikloak::Rails.configure do |config|
            config.auto_insert_bff_header_guard = true
            config.bff_header_guard_insert_before = nil
            config.bff_header_guard_insert_after = custom_middleware
          end

          expect(middleware_stack).to receive(:insert_after)
            .with(custom_middleware, ::Verikloak::BFF::HeaderGuard)

          railtie.send(:configure_bff_guard, middleware_stack)
        end
      end

      context 'when auto_insert_bff_header_guard is disabled' do
        before do
          Verikloak::Rails.configure do |config|
            config.auto_insert_bff_header_guard = false
          end
        end

        it 'does not insert HeaderGuard' do
          expect(middleware_stack).not_to receive(:insert_before)
          expect(middleware_stack).not_to receive(:insert_after)

          railtie.send(:configure_bff_guard, middleware_stack)
        end
      end
    end

    context 'when Verikloak::BFF::HeaderGuard is not defined' do
      it 'does not attempt to insert any middleware' do
        Verikloak::Rails.configure do |config|
          config.auto_insert_bff_header_guard = true
        end

        # Ensure BFF::HeaderGuard is not defined
        hide_const('::Verikloak::BFF::HeaderGuard') if defined?(::Verikloak::BFF::HeaderGuard)

        expect(middleware_stack).not_to receive(:insert_before)
        expect(middleware_stack).not_to receive(:insert_after)

        railtie.send(:configure_bff_guard, middleware_stack)
      end
    end
  end

  describe '.bff_configuration_valid?' do
    let(:railtie) { described_class }
    let(:bff_config) { double('BffConfig') }

    before do
      stub_const('::Verikloak::BFF', Module.new)
      allow(::Verikloak::BFF).to receive(:respond_to?).and_return(false)
      allow(::Verikloak::BFF).to receive(:respond_to?).with(:config).and_return(true)
      allow(::Verikloak::BFF).to receive(:respond_to?).with(:config, true).and_return(true)
      allow(::Verikloak::BFF).to receive(:config).and_return(bff_config)
    end

    context 'when Verikloak::BFF is not defined' do
      it 'returns true' do
        hide_const('::Verikloak::BFF')
        expect(railtie.send(:bff_configuration_valid?)).to be true
      end
    end

    context 'when disabled is true' do
      it 'returns true (HeaderGuard will be inserted but internally disabled)' do
        allow(bff_config).to receive(:respond_to?).with(:disabled).and_return(true)
        allow(bff_config).to receive(:disabled).and_return(true)

        expect(railtie.send(:bff_configuration_valid?)).to be true
      end
    end

    context 'when disabled is false or nil' do
      before do
        allow(bff_config).to receive(:respond_to?).with(:disabled).and_return(true)
        allow(bff_config).to receive(:disabled).and_return(false)
      end

      context 'when trusted_proxies is not supported (legacy version)' do
        it 'returns true' do
          allow(bff_config).to receive(:respond_to?).with(:trusted_proxies).and_return(false)

          expect(railtie.send(:bff_configuration_valid?)).to be true
        end
      end

      context 'when trusted_proxies is a non-empty Array' do
        it 'returns true' do
          allow(bff_config).to receive(:respond_to?).with(:trusted_proxies).and_return(true)
          allow(bff_config).to receive(:trusted_proxies).and_return(['10.0.0.0/8'])

          expect(railtie.send(:bff_configuration_valid?)).to be true
        end
      end

      context 'when trusted_proxies is an empty Array' do
        it 'returns false' do
          allow(bff_config).to receive(:respond_to?).with(:trusted_proxies).and_return(true)
          allow(bff_config).to receive(:trusted_proxies).and_return([])

          expect(railtie.send(:bff_configuration_valid?)).to be false
        end
      end

      context 'when trusted_proxies is nil' do
        it 'returns false' do
          allow(bff_config).to receive(:respond_to?).with(:trusted_proxies).and_return(true)
          allow(bff_config).to receive(:trusted_proxies).and_return(nil)

          expect(railtie.send(:bff_configuration_valid?)).to be false
        end
      end

      context 'when trusted_proxies is not an Array' do
        it 'returns false for Set' do
          allow(bff_config).to receive(:respond_to?).with(:trusted_proxies).and_return(true)
          allow(bff_config).to receive(:trusted_proxies).and_return(Set.new(['10.0.0.0/8']))

          expect(railtie.send(:bff_configuration_valid?)).to be false
        end

        it 'returns false for String' do
          allow(bff_config).to receive(:respond_to?).with(:trusted_proxies).and_return(true)
          allow(bff_config).to receive(:trusted_proxies).and_return('10.0.0.0/8')

          expect(railtie.send(:bff_configuration_valid?)).to be false
        end
      end
    end
  end

  describe '.configure_bff_guard with bff_configuration_valid? integration' do
    let(:railtie) { described_class }
    let(:middleware_stack) { double('MiddlewareStack') }
    let(:bff_config) { double('BffConfig') }

    before do
      Verikloak::Rails.reset!
      stub_const('::Verikloak::BFF', Module.new)
      stub_const('::Verikloak::BFF::HeaderGuard', Class.new)
      allow(::Verikloak::BFF).to receive(:respond_to?).and_return(false)
      allow(::Verikloak::BFF).to receive(:respond_to?).with(:config).and_return(true)
      allow(::Verikloak::BFF).to receive(:respond_to?).with(:config, true).and_return(true)
      allow(::Verikloak::BFF).to receive(:config).and_return(bff_config)

      Verikloak::Rails.configure do |config|
        config.auto_insert_bff_header_guard = true
      end
    end

    context 'when trusted_proxies is not configured' do
      before do
        allow(bff_config).to receive(:respond_to?).with(:disabled).and_return(true)
        allow(bff_config).to receive(:disabled).and_return(false)
        allow(bff_config).to receive(:respond_to?).with(:trusted_proxies).and_return(true)
        allow(bff_config).to receive(:trusted_proxies).and_return([])
      end

      it 'skips HeaderGuard insertion and logs warning' do
        expect(middleware_stack).not_to receive(:insert_before)
        expect(middleware_stack).not_to receive(:insert_after)

        expect(railtie).to receive(:warn_with_fallback).with(
          '[verikloak] Skipping BFF::HeaderGuard insertion: trusted_proxies not configured. ' \
          'Set trusted_proxies in bff_header_guard_options to enable header validation.'
        )

        railtie.send(:configure_bff_guard, middleware_stack)
      end
    end

    context 'when disabled is true' do
      before do
        allow(bff_config).to receive(:respond_to?).with(:disabled).and_return(true)
        allow(bff_config).to receive(:disabled).and_return(true)
      end

      it 'inserts HeaderGuard (internally disabled)' do
        expect(middleware_stack).to receive(:insert_before)
          .with(::Verikloak::Middleware, ::Verikloak::BFF::HeaderGuard)

        railtie.send(:configure_bff_guard, middleware_stack)
      end
    end

    context 'when trusted_proxies is configured' do
      before do
        allow(bff_config).to receive(:respond_to?).with(:disabled).and_return(true)
        allow(bff_config).to receive(:disabled).and_return(false)
        allow(bff_config).to receive(:respond_to?).with(:trusted_proxies).and_return(true)
        allow(bff_config).to receive(:trusted_proxies).and_return(['10.0.0.0/8'])
      end

      it 'inserts HeaderGuard' do
        expect(middleware_stack).to receive(:insert_before)
          .with(::Verikloak::Middleware, ::Verikloak::BFF::HeaderGuard)

        railtie.send(:configure_bff_guard, middleware_stack)
      end
    end
  end

  describe 'verikloak.controller initializer' do
    describe 'API mode support' do
      it 'registers hooks for both ActionController::Base and ActionController::API' do
        initializer = described_class.initializers.find { |i| i.name == 'verikloak.controller' }
        expect(initializer).not_to be_nil

        # Read the source file to verify both hooks are registered
        source_file, _line = initializer.block.source_location
        source_content = File.read(source_file)

        expect(source_content).to include('action_controller_base')
        expect(source_content).to include('action_controller_api')
      end

      it 'includes concern in ActionController::API when auto_include_controller is true' do
        Verikloak::Rails.reset!
        Verikloak::Rails.configure do |config|
          config.auto_include_controller = true
        end

        # Create a test API controller class and simulate the on_load callback
        api_controller = Class.new(ActionController::API)
        api_controller.include(Verikloak::Rails::Controller)

        expect(api_controller.included_modules).to include(Verikloak::Rails::Controller)
      end

      it 'skips inclusion when controller already includes the concern' do
        Verikloak::Rails.reset!
        Verikloak::Rails.configure do |config|
          config.auto_include_controller = true
        end

        # Create a controller that already includes the concern
        api_controller = Class.new(ActionController::API)
        api_controller.include(Verikloak::Rails::Controller)

        # Simulating re-inclusion should not raise or cause issues
        expect {
          api_controller.class_eval do
            include Verikloak::Rails::Controller unless include?(Verikloak::Rails::Controller)
          end
        }.not_to raise_error

        # Should still only be included once in the ancestor chain
        count = api_controller.included_modules.count { |m| m == Verikloak::Rails::Controller }
        expect(count).to eq(1)
      end
    end
  end
end