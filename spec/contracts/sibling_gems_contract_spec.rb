# frozen_string_literal: true

# Contract specs that exercise verikloak-rails against the REAL sibling gems
# (verikloak core, verikloak-pundit, verikloak-bff, verikloak-audience)
# instead of the hand-rolled fakes used by the unit suite. They exist to
# catch interface drift that fakes cannot (e.g. constructor signature
# changes in a sibling gem).
#
# These specs are tagged :contract and excluded from the default run (see
# spec_helper). The CI "contracts" job runs them in a dedicated process:
#
#   BUNDLE_GEMFILE=gemfiles/contracts.Gemfile bundle install
#   VERIKLOAK_CONTRACTS=true BUNDLE_GEMFILE=gemfiles/contracts.Gemfile \
#     bundle exec rspec spec/contracts
#
# All gem requires happen inside before(:context) hooks — never at file load
# time — so loading this file in the unit-suite process (where the examples
# are filtered out) cannot clobber the unit suite's stubs.
require 'spec_helper'
require 'ostruct'

RSpec.describe 'verikloak (core gem) contract', :contract do
  before(:context) do
    require 'verikloak'
    require 'verikloak/rails'
  end

  before do
    Verikloak::Rails.reset!
  end

  after do
    Verikloak::Rails.reset!
  end

  it 'accepts every key produced by Configuration#middleware_options' do
    Verikloak::Rails.configure do |c|
      c.discovery_url = 'https://idp.example.com/.well-known/openid-configuration'
      c.audience = 'rails-api'
      c.issuer = 'https://idp.example.com/realms/example'
      c.leeway = 30
      c.skip_paths = ['/health']
      c.token_verify_options = { verify_iat: false }
      c.decoder_cache_limit = 8
      c.jwks_refresh_interval = 30
      c.token_env_key = 'custom.token'
      c.user_env_key = 'custom.user'
      c.allow_http = false
    end

    app = ->(_env) { [204, {}, []] }
    options = Verikloak::Rails.config.middleware_options

    expect { ::Verikloak::Middleware.new(app, **options) }.not_to raise_error
  end

  it 'uses the same default env keys as Configuration' do
    expect(::Verikloak::Middleware::DEFAULT_TOKEN_ENV_KEY)
      .to eq(Verikloak::Rails::Configuration::DEFAULT_TOKEN_ENV_KEY)
    expect(::Verikloak::Middleware::DEFAULT_USER_ENV_KEY)
      .to eq(Verikloak::Rails::Configuration::DEFAULT_USER_ENV_KEY)
  end

  it 'exposes the Error signature the concern relies on' do
    error = ::Verikloak::Error.new('Unauthorized', code: 'unauthorized')

    expect(error.message).to eq('Unauthorized')
    expect(error.code).to eq('unauthorized')
  end

  it 'exposes ErrorResponse.sanitize_header_value used by ErrorRenderer' do
    require 'verikloak/error_response'

    expect(::Verikloak::ErrorResponse).to respond_to(:sanitize_header_value)
    expect(::Verikloak::ErrorResponse.sanitize_header_value("a\r\nb")).not_to include("\r")
  end

  it 'provides the SkipPathMatcher mixin wrapped by SkipPathChecker' do
    checker = Verikloak::Rails::SkipPathChecker.new(['/health', '/public/*'])

    expect(checker.skip?('/health')).to be(true)
    expect(checker.skip?('/public/deep/path')).to be(true)
    expect(checker.skip?('/api/users')).to be(false)
  end
end

RSpec.describe 'verikloak-pundit contract', :contract do
  before(:context) do
    require 'verikloak/pundit'
    require 'verikloak/rails/testing/helpers'
  rescue LoadError
    skip 'verikloak-pundit is not installed (run with gemfiles/contracts.Gemfile)'
  end

  let(:helper) { Class.new { include Verikloak::Rails::Testing::Helpers }.new }
  let(:user) { OpenStruct.new(uid: 'u-1', email: 'a@example.com') }

  it 'builds a real UserContext from claims' do
    ctx = helper.build_pundit_user_context({ 'sub' => 'u-1', 'email' => 'a@example.com' })

    expect(ctx).to be_a(::Verikloak::Pundit::UserContext)
    expect(ctx.sub).to eq('u-1')
  end

  it 'forwards resource_client to the real constructor' do
    ctx = helper.build_pundit_user_context({ 'sub' => 'u-1' }, resource_client: 'rails-api')

    expect(ctx.resource_client).to eq('rails-api')
  end

  it '#build_admin_user_context works end-to-end against the real gem' do
    ctx = helper.build_admin_user_context(user)

    expect(ctx).to be_a(::Verikloak::Pundit::UserContext)
    expect(ctx.sub).to eq('u-1')
  end

  it '#build_user_user_context works end-to-end against the real gem' do
    ctx = helper.build_user_user_context(user)

    expect(ctx).to be_a(::Verikloak::Pundit::UserContext)
    expect(ctx.sub).to eq('u-1')
  end
end

RSpec.describe 'verikloak-bff contract', :contract do
  before(:context) do
    require 'verikloak-bff'
    require 'verikloak/rails'
  rescue LoadError
    skip 'verikloak-bff is not installed (run with gemfiles/contracts.Gemfile)'
  end

  it 'exposes the configuration surface BffConfigurator relies on' do
    expect(::Verikloak::BFF).to respond_to(:configure)
    expect(::Verikloak::BFF).to respond_to(:config)

    config = ::Verikloak::BFF.config
    expect(config).to respond_to(:trusted_proxies)
    expect(config).to respond_to(:trusted_proxies=)
    expect(config).to respond_to(:disabled)
  end

  it 'accepts a Hash bridged through BffConfigurator.apply_configuration' do
    Verikloak::Rails::BffConfigurator.apply_configuration(
      ::Verikloak::BFF, { trusted_proxies: ['127.0.0.1'] }
    )

    expect(::Verikloak::BFF.config.trusted_proxies).to eq(['127.0.0.1'])
  end

  it 'stores the inner app in @app (MiddlewareStub passthrough contract)' do
    inner = ->(_env) { [204, {}, []] }
    # HeaderGuard validates its configuration at construction time and
    # requires trusted_proxies (or disabled: true), so pass explicit opts
    # to keep this example independent of global BFF.config state.
    guard = ::Verikloak::BFF::HeaderGuard.new(inner, trusted_proxies: ['127.0.0.1'])

    expect(guard.instance_variable_get(:@app)).to equal(inner)
  end
end

RSpec.describe 'verikloak-audience contract', :contract do
  before(:context) do
    require 'verikloak/audience'
  rescue LoadError
    skip 'verikloak-audience is not installed (run with gemfiles/contracts.Gemfile)'
  end

  it 'stores the inner app in @app (MiddlewareStub passthrough contract)' do
    inner = ->(_env) { [204, {}, []] }
    middleware = ::Verikloak::Audience::Middleware.new(inner, required_aud: ['rails-api'])

    expect(middleware.instance_variable_get(:@app)).to equal(inner)
  end
end
