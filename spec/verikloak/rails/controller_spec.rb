# frozen_string_literal: true

require 'spec_helper'
require 'verikloak/rails'
require 'verikloak/rails/controller'

RSpec.describe Verikloak::Rails::Controller do
  let(:controller_class) do
    Class.new do
      class << self
        def before_action(*) = nil
        def rescue_from(*) = nil
        def around_action(*) = nil
      end

      include Verikloak::Rails::Controller

      attr_reader :request, :render_calls

      def initialize(request)
        @request = request
        @render_calls = []
      end

      def render(**options)
        @render_calls << options
      end
    end
  end

  let(:controller) { controller_class.new(request) }
  let(:env) { { 'verikloak.token' => nil } }
  let(:request) do
    instance_double('ActionDispatch::Request', env: env, headers: {}, request_id: nil)
  end

  before do
    Verikloak::Rails.instance_variable_set(:@config, nil)
  end

  describe '#current_token' do
    it 'falls back to RequestStore when the Rack env token is missing' do
      store_class = Class.new do
        class << self
          def store
            @store ||= {}
          end
        end
      end

      stub_const('RequestStore', store_class)
      RequestStore.store[:verikloak_token] = 'stored-token'

      expect(controller.current_token).to eq('stored-token')
    end
  end

  describe '#_verikloak_base_logger' do
    it 'walks nested loggers to locate the innermost logger with error support' do
      inner_logger = Class.new do
        def error(*) = nil
      end.new

      middle_logger = Struct.new(:logger).new(inner_logger)
      root_logger = Struct.new(:logger).new(middle_logger)

      allow(::Rails).to receive(:logger).and_return(root_logger)

      expect(controller.send(:_verikloak_base_logger)).to equal(inner_logger)
    end
  end

  describe '#_verikloak_log_internal_error' do
    it 'swallows logging failures from the chosen logger' do
      failing_logger = Class.new do
        def error(*)
          raise StandardError, 'logging failed'
        end
      end.new

      allow(controller).to receive(:_verikloak_base_logger).and_return(failing_logger)

      exception = RuntimeError.new('boom')
      exception.set_backtrace(['line:42'])

      expect { controller.send(:_verikloak_log_internal_error, exception) }.not_to raise_error
    end
  end
end
