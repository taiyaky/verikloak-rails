# frozen_string_literal: true

require_relative 'lib/verikloak/rails/version'

Gem::Specification.new do |spec|
  spec.name        = 'verikloak-rails'
  spec.version     = Verikloak::Rails::VERSION
  spec.authors     = ['taiyaky']

  spec.summary     = 'Rails integration for Verikloak (Keycloak JWT via Rack middleware)'
  spec.description = 'Rails integration for Verikloak: auto middleware, helpers, and standardized JSON errors.'

  spec.homepage    = 'https://github.com/taiyaky/verikloak-rails'
  spec.license     = 'MIT'

  spec.files         = Dir['lib/**/*.{rb,erb}'] + %w[README.md LICENSE CHANGELOG.md]
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 3.1'

  # Runtime dependencies
  spec.add_dependency 'rack', '>= 2.2', '< 4.0'
  spec.add_dependency 'rails', '>= 6.1', '< 9.0'
  spec.add_dependency 'verikloak', '~> 1.0'
  # Metadata for RubyGems
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri']   = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['bug_tracker_uri'] = "#{spec.homepage}/issues"
  spec.metadata['documentation_uri'] = "https://rubydoc.info/gems/verikloak-rails/#{Verikloak::Rails::VERSION}"
  spec.metadata['rubygems_mfa_required'] = 'true'
end
