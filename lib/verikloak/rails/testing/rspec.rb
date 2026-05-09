# frozen_string_literal: true

# RSpec integration for Verikloak::Rails::Testing.
#
# Require this file from `spec/rails_helper.rb` (or `spec/spec_helper.rb`)
# to:
#
# 1. Mix {Verikloak::Rails::Testing::Helpers} into request and policy specs.
# 2. Register the shared contexts:
#    - `"with verikloak admin auth"`
#    - `"with verikloak user auth"`
#    - `"with verikloak custom auth"`
#
# The shared contexts assume a `current_user` factory exists in the host
# application (e.g. `create(:user)`). Override `let(:current_user)` to
# inject a different user object.

require 'verikloak/rails/testing/helpers'

raise 'verikloak/rails/testing/rspec requires RSpec' unless defined?(RSpec)

RSpec.configure do |config|
  config.include Verikloak::Rails::Testing::Helpers, type: :request
  config.include Verikloak::Rails::Testing::Helpers, type: :controller
  config.include Verikloak::Rails::Testing::Helpers, type: :policy
end

RSpec.shared_context 'with verikloak admin auth' do
  let(:current_user) { create(:user) }

  before do
    stub_verikloak_middleware(build_admin_claims(current_user))
  end
end

RSpec.shared_context 'with verikloak user auth' do
  let(:current_user) { create(:user) }

  before do
    stub_verikloak_middleware(build_user_claims(current_user))
  end
end

RSpec.shared_context 'with verikloak custom auth' do
  let(:current_user) { create(:user) }
  let(:verikloak_groups)       { [] }
  let(:verikloak_extra_claims) { {} }

  before do
    stub_verikloak_middleware(
      build_jwt_claims(current_user, groups: verikloak_groups, extra_claims: verikloak_extra_claims)
    )
  end
end
