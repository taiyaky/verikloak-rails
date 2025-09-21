# frozen_string_literal: true

require 'spec_helper'

require 'active_support/ordered_options'
require 'rails/railtie'
require 'rails/rack/logger'

$LOAD_PATH.unshift File.expand_path('stubs', __dir__)
require 'verikloak/middleware'

require 'verikloak/rails'

RSpec.describe Verikloak::Rails::Railtie do
  before do
    Verikloak::Rails.instance_variable_set(:@config, nil)
  end

  let(:configure_initializer) do
    described_class.initializers.find { |i| i.name == 'verikloak.configure' }
  end

  class FakeMiddlewareStack
    attr_reader :operations

    def initialize
      @operations = []
    end

    def insert_after(target, middleware, *args, **kwargs)
      @operations << [:after, target, middleware, args, kwargs]
    end

    def insert_before(target, middleware, *args, **kwargs)
      @operations << [:before, target, middleware, args, kwargs]
    end

    def use(middleware, *args, **kwargs)
      @operations << [:use, nil, middleware, args, kwargs]
    end
  end

  class FakeApp
    attr_reader :config, :middleware

    def initialize
      @config = Struct.new(:verikloak).new(ActiveSupport::OrderedOptions.new)
      @middleware = FakeMiddlewareStack.new
    end
  end

  let(:app) { FakeApp.new }

  def run_initializer
    configure_initializer.run(app)
  end

  it 'inserts base middleware after Rails::Rack::Logger by default' do
    stub_const('Verikloak::Bff::HeaderGuard', Class.new)
    run_initializer
    operation = app.middleware.operations.find { |kind, _, middleware, _, _| kind == :after && middleware == Verikloak::Middleware }
    expect(operation).not_to be_nil
    expect(operation[1]).to eq(::Rails::Rack::Logger)
  end

  it 'supports configuring insert_before' do
    app.config.verikloak.middleware_insert_before = :some_middleware
    stub_const('Verikloak::Bff::HeaderGuard', Class.new)
    run_initializer
    operation = app.middleware.operations.find { |kind, target, middleware, _, _| kind == :before && middleware == Verikloak::Middleware }
    expect(operation).not_to be_nil
    expect(operation[1]).to eq(:some_middleware)
  end

  it 'supports configuring insert_after' do
    app.config.verikloak.middleware_insert_after = :another
    stub_const('Verikloak::Bff::HeaderGuard', Class.new)
    run_initializer
    operation = app.middleware.operations.find { |kind, target, middleware, _, _| kind == :after && middleware == Verikloak::Middleware }
    expect(operation).not_to be_nil
    expect(operation[1]).to eq(:another)
  end

  it 'auto inserts the BFF header guard before the base middleware when present' do
    guard = Class.new
    stub_const('Verikloak::Bff::HeaderGuard', guard)
    run_initializer
    expect(app.middleware.operations).to include([:before, Verikloak::Middleware, guard, [], {}])
  end

  it 'inserts the BFF header guard before a configured middleware when requested' do
    app.config.verikloak.bff_header_guard_insert_before = :another_guard
    guard = Class.new
    stub_const('Verikloak::Bff::HeaderGuard', guard)
    run_initializer
    expect(app.middleware.operations).to include([:before, :another_guard, guard, [], {}])
  end

  it 'inserts the BFF header guard after a configured middleware when requested' do
    app.config.verikloak.bff_header_guard_insert_after = :after_target
    guard = Class.new
    stub_const('Verikloak::Bff::HeaderGuard', guard)
    run_initializer
    expect(app.middleware.operations).to include([:after, :after_target, guard, [], {}])
  end

  it 'skips inserting the BFF header guard when disabled' do
    app.config.verikloak.auto_insert_bff_header_guard = false
    guard = Class.new
    stub_const('Verikloak::Bff::HeaderGuard', guard)
    run_initializer
    expect(app.middleware.operations.none? { |_, _, middleware, _, _| middleware == guard }).to be(true)
  end

  it 'disables Pundit rescue when verikloak-pundit is present and config is not set' do
    stub_const('Verikloak::Pundit', Module.new)
    run_initializer
    expect(Verikloak::Rails.config.rescue_pundit).to eq(false)
  end

  it 'respects explicit rescue_pundit configuration even when verikloak-pundit is present' do
    app.config.verikloak.rescue_pundit = true
    stub_const('Verikloak::Pundit', Module.new)
    run_initializer
    expect(Verikloak::Rails.config.rescue_pundit).to eq(true)
  end
end
