# frozen_string_literal: true

require 'spec_helper'
require 'ostruct'
require 'verikloak/rails/testing/helpers'

RSpec.describe Verikloak::Rails::Testing::Helpers do
  let(:helper) { Class.new { include Verikloak::Rails::Testing::Helpers }.new }
  let(:user) { OpenStruct.new(uid: 'u-1', email: 'a@example.com') }

  describe '#build_pundit_user_context' do
    it 'raises when verikloak-pundit is not loaded' do
      hide_const('Verikloak::Pundit') if defined?(::Verikloak::Pundit)
      expect { helper.build_pundit_user_context({}) }
        .to raise_error(RuntimeError, /verikloak-pundit/)
    end

    context 'when verikloak-pundit is loaded' do
      before do
        # Mirrors verikloak-pundit 1.0's UserContext#initialize signature:
        # a single positional claims Hash plus keyword options. Keeping the
        # fake aligned with the real constructor is what the contract specs
        # in spec/contracts verify against the real gem.
        ctx_class = Class.new do
          attr_reader :claims, :resource_client, :config

          def initialize(claims, resource_client: nil, config: nil)
            @claims = claims
            @resource_client = resource_client
            @config = config
          end
        end
        stub_const('Verikloak::Pundit', Module.new)
        stub_const('Verikloak::Pundit::UserContext', ctx_class)
      end

      it 'wraps claims into a UserContext' do
        ctx = helper.build_pundit_user_context({ 'sub' => 'u-1' })
        expect(ctx.claims).to eq('sub' => 'u-1')
      end

      it 'forwards keyword options to UserContext' do
        ctx = helper.build_pundit_user_context({ 'sub' => 'u-1' }, resource_client: 'rails-api')
        expect(ctx.resource_client).to eq('rails-api')
      end

      it '#build_admin_user_context produces admin claims' do
        ctx = helper.build_admin_user_context(user)
        expect(ctx.claims['groups']).to eq(['/admin'])
      end

      it '#build_user_user_context produces user claims' do
        ctx = helper.build_user_user_context(user)
        expect(ctx.claims['groups']).to eq(['/user'])
      end
    end
  end
end
