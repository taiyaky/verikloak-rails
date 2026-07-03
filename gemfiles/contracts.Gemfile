# frozen_string_literal: true

# Gemfile for the CI "contracts" job: runs spec/contracts against the REAL
# sibling gems instead of the unit suite's fakes.
#
#   BUNDLE_GEMFILE=gemfiles/contracts.Gemfile bundle install
#   VERIKLOAK_CONTRACTS=true BUNDLE_GEMFILE=gemfiles/contracts.Gemfile \
#     bundle exec rspec spec/contracts

eval_gemfile File.expand_path('../Gemfile', __dir__)

group :test do
  gem 'verikloak-audience', '>= 1.0'
  gem 'verikloak-bff', '>= 1.0'
  gem 'verikloak-pundit', '>= 1.0'
end
