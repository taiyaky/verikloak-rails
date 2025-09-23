# frozen_string_literal: true

require 'spec_helper'

# Load Rails and ActionDispatch for the test
require 'rails'
require 'action_controller/railtie'

require 'verikloak/rails'

RSpec.describe Verikloak::Rails::Railtie, type: :railtie do
  describe '.middleware_insert_after_candidates' do
    let(:railtie) { described_class }
    
    before do
      Verikloak::Rails.reset!
    end

    context 'with default configuration' do
      it 'returns fallback middleware candidates when configured value is nil' do
        Verikloak::Rails.configure do |config|
          config.middleware_insert_after = nil
        end

        candidates = railtie.send(:middleware_insert_after_candidates)
        
        # Should contain only the defaults (no configured value)
        expect(candidates).to include(::Rails::Rack::Logger) if defined?(::Rails::Rack::Logger)
        expect(candidates).to include(::ActionDispatch::Executor) if defined?(::ActionDispatch::Executor)
        expect(candidates).to include(::Rack::Head) if defined?(::Rack::Head)
        expect(candidates).to include(::Rack::Runtime) if defined?(::Rack::Runtime)
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
        expect(candidates).to include(::Rails::Rack::Logger) if defined?(::Rails::Rack::Logger)
        expect(candidates).to include(::ActionDispatch::Executor) if defined?(::ActionDispatch::Executor)
      end
    end

    context 'with Rails 8 compatibility' do
      it 'handles Rails 8 middleware stack gracefully' do
        # Ensure we're testing with the actual middleware classes
        expect(defined?(::Rails::Rack::Logger)).to eq('constant')
        expect(defined?(::ActionDispatch::Executor)).to eq('constant')
        expect(defined?(::Rack::Head)).to eq('constant')
        expect(defined?(::Rack::Runtime)).to eq('constant')

        Verikloak::Rails.configure do |config|
          config.middleware_insert_after = nil
        end

        candidates = railtie.send(:middleware_insert_after_candidates)
        
        # All expected middleware should be present in Rails 8
        expect(candidates).to include(::Rails::Rack::Logger)
        expect(candidates).to include(::ActionDispatch::Executor)
        expect(candidates).to include(::Rack::Head)
        expect(candidates).to include(::Rack::Runtime)
        
        # Should be unique (no duplicates)
        expect(candidates.uniq).to eq(candidates)
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
end