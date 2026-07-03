# frozen_string_literal: true

require 'spec_helper'
require_relative '../../support/verikloak_stubs'
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
    Verikloak::Rails.reset!
  end

  # Several groups below mutate the process-global configuration (custom env
  # keys, render_500_json, rescue_pundit); reset it afterwards so the values
  # cannot leak into other spec files under random ordering.
  after do
    Verikloak::Rails.reset!
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

  describe 'custom env keys' do
    let(:env) { { 'custom.user' => { 'sub' => 'user-9' }, 'custom.token' => 'tok-9' } }

    before do
      Verikloak::Rails.config.user_env_key = 'custom.user'
      Verikloak::Rails.config.token_env_key = 'custom.token'
    end

    it 'reads claims from the configured user_env_key' do
      expect(controller.current_user_claims).to eq('sub' => 'user-9')
    end

    it 'reads the token from the configured token_env_key' do
      expect(controller.current_token).to eq('tok-9')
    end

    it 'treats the request as authenticated' do
      expect(controller.authenticated?).to be(true)
    end
  end

  describe 'error handler registration at include time' do
    let(:registering_class) do
      Class.new do
        class << self
          def rescued_classes = (@rescued_classes ||= [])
          def before_action(*) = nil
          def around_action(*) = nil

          def rescue_from(klass, **_opts, &_block)
            rescued_classes << klass
          end
        end
      end
    end

    before do
      stub_const('Pundit::NotAuthorizedError', Class.new(StandardError))
    end

    it 'skips the StandardError and Pundit handlers when disabled, preserving cause-chain traversal' do
      Verikloak::Rails.config.render_500_json = false
      Verikloak::Rails.config.rescue_pundit = false

      registering_class.include(described_class)

      expect(registering_class.rescued_classes).to eq([Verikloak::Error])
    end

    it 'registers both handlers when enabled at include time' do
      Verikloak::Rails.config.render_500_json = true
      Verikloak::Rails.config.rescue_pundit = true

      registering_class.include(described_class)

      expect(registering_class.rescued_classes)
        .to eq([StandardError, Pundit::NotAuthorizedError, Verikloak::Error])
    end
  end

  describe '#_verikloak_handle_standard_error' do
    let(:exception) { StandardError.new('boom') }

    it 're-raises when render_500_json is disabled' do
      Verikloak::Rails.config.render_500_json = false
      expect { controller.send(:_verikloak_handle_standard_error, exception) }
        .to raise_error(exception)
      expect(controller.render_calls).to be_empty
    end

    it 'renders the JSON 500 when render_500_json is enabled at request time' do
      Verikloak::Rails.config.render_500_json = true
      allow(controller).to receive(:_verikloak_log_internal_error)

      controller.send(:_verikloak_handle_standard_error, exception)

      expect(controller.render_calls.last).to include(
        json: { error: 'internal_server_error', message: 'An unexpected error occurred' },
        status: :internal_server_error
      )
    end
  end

  describe '#_verikloak_handle_pundit_error' do
    let(:exception) { StandardError.new('nope') }

    it 'renders 403 JSON when rescue_pundit is enabled' do
      Verikloak::Rails.config.rescue_pundit = true

      controller.send(:_verikloak_handle_pundit_error, exception)

      expect(controller.render_calls.last).to include(
        json: { error: 'forbidden', message: 'nope' },
        status: :forbidden
      )
    end

    it 'falls back to the JSON 500 when rescue_pundit is disabled but render_500_json is enabled' do
      Verikloak::Rails.config.rescue_pundit = false
      Verikloak::Rails.config.render_500_json = true
      allow(controller).to receive(:_verikloak_log_internal_error)

      controller.send(:_verikloak_handle_pundit_error, exception)

      expect(controller.render_calls.last).to include(status: :internal_server_error)
    end

    it 're-raises when both rescues are disabled' do
      Verikloak::Rails.config.rescue_pundit = false
      Verikloak::Rails.config.render_500_json = false

      expect { controller.send(:_verikloak_handle_pundit_error, exception) }
        .to raise_error(exception)
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

  describe '#authenticate_user!' do
    let(:request) do
      instance_double('ActionDispatch::Request', env: env, headers: {}, request_id: nil, path_info: request_path)
    end
    let(:request_path) { '/api/protected' }

    context 'when the path matches a configured skip_path' do
      before do
        Verikloak::Rails.config.skip_paths = ['/rails/active_storage/*', '/health']
      end

      let(:request_path) { '/rails/active_storage/blobs/proxy/abc123' }

      it 'skips authentication and does not render an error' do
        controller.authenticate_user!
        expect(controller.render_calls).to be_empty
      end
    end

    context 'when the path exactly matches a skip_path' do
      before do
        Verikloak::Rails.config.skip_paths = ['/health']
      end

      let(:request_path) { '/health' }

      it 'skips authentication' do
        controller.authenticate_user!
        expect(controller.render_calls).to be_empty
      end
    end

    context 'when the path does not match any skip_path and user is unauthenticated' do
      before do
        Verikloak::Rails.config.skip_paths = ['/health']
      end

      let(:request_path) { '/api/protected' }

      it 'invokes the error renderer' do
        renderer = instance_double('Verikloak::Rails::ErrorRenderer')
        allow(renderer).to receive(:render)
        Verikloak::Rails.config.error_renderer = renderer

        controller.authenticate_user!
        expect(renderer).to have_received(:render).with(controller, an_instance_of(Verikloak::Error))
      end
    end

    context 'when the path does not match any skip_path and user is authenticated' do
      before do
        Verikloak::Rails.config.skip_paths = ['/health']
        env['verikloak.user'] = { 'sub' => 'user-1' }
      end

      let(:request_path) { '/api/protected' }

      it 'does not render an error' do
        controller.authenticate_user!
        expect(controller.render_calls).to be_empty
      end
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
