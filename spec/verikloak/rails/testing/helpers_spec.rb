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
      expect { helper.build_pundit_user_context(user, {}) }
        .to raise_error(RuntimeError, /verikloak-pundit/)
    end

    context 'when verikloak-pundit is loaded' do
      before do
        ctx_class = Struct.new(:user, :claims)
        stub_const('Verikloak::Pundit', Module.new)
        stub_const('Verikloak::Pundit::UserContext', ctx_class)
      end

      it 'wraps user and claims into a UserContext' do
        ctx = helper.build_pundit_user_context(user, 'sub' => 'u-1')
        expect(ctx.user).to eq(user)
        expect(ctx.claims).to eq('sub' => 'u-1')
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
