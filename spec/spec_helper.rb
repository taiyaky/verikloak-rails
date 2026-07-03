# frozen_string_literal: true

require 'bundler/setup'

# Enable SimpleCov coverage reporting when CI sets SIMPLECOV=true
if ENV['SIMPLECOV']
  begin
    require 'simplecov'
    SimpleCov.start do
      enable_coverage :branch
      add_filter %r{^/spec/}
    end
  rescue LoadError
    warn '[spec_helper] simplecov not available; skipping coverage'
  end
end

require 'rspec'

# Load only the files under test to avoid hard dependencies during unit tests.
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

# Common library requires for unit specs
require 'verikloak/rails/error_renderer'

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.mock_with :rspec do |m|
    m.verify_partial_doubles = true
  end

  # Run specs in random order to surface order dependencies.
  config.order = :random
  Kernel.srand config.seed

  # Several files mutate the process-global Verikloak::Rails configuration
  # (custom env keys, render_500_json, ...). Their own before-hooks self-heal
  # within a file, but whatever the file's last example set would otherwise
  # leak into the next file under random ordering (e.g. seed 29776 broke the
  # MiddlewareStub default-key specs). Reset after every example, but only
  # when the library is loaded — some unit specs run without it.
  config.after do
    Verikloak::Rails.reset! if defined?(Verikloak::Rails) && Verikloak::Rails.respond_to?(:reset!)
  end

  # Contract specs (spec/contracts) exercise the REAL sibling gems and must
  # run in a dedicated process so they do not collide with the fakes/stubs
  # used by the unit suite. CI runs them in the "contracts" job:
  #   BUNDLE_GEMFILE=gemfiles/contracts.Gemfile bundle install
  #   VERIKLOAK_CONTRACTS=true BUNDLE_GEMFILE=gemfiles/contracts.Gemfile \
  #     bundle exec rspec spec/contracts
  config.filter_run_excluding :contract unless ENV['VERIKLOAK_CONTRACTS'] == 'true'
end
