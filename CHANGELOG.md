# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.3.1] - 2026-01-01

### Added
- **API mode support**: `auto_include_controller` now automatically includes
  `Verikloak::Rails::Controller` in both `ActionController::Base` and `ActionController::API`
  - Rails API-only applications (`rails new myapp --api`) now work out of the box
  - Skip logic prevents duplicate inclusion when controller already includes the concern

### Changed
- **Generator template improved**: `initializer.rb.erb` now includes:
  - Descriptive comments for each configuration option
  - ENV variable support for `auto_include_controller` (`VERIKLOAK_AUTO_INCLUDE`)
  - ENV variable prefix changed from `VERIKLOAK_AUDIENCE` to `KEYCLOAK_AUDIENCE` for consistency

### Documentation
- README updated with API mode usage example

---

## [0.3.0] - 2026-01-01

### Changed
- **BFF HeaderGuard detection**: Now only supports `Verikloak::BFF::HeaderGuard` (uppercase)
  - Removed fallback support for `Verikloak::Bff::HeaderGuard` (lowercase)
  - This simplifies the codebase and aligns with verikloak-bff's official namespace
- `configure_bff_library` method simplified to only target `Verikloak::BFF` namespace

### Added
- Comprehensive test coverage for `configure_bff_guard` method
  - Tests for default insertion position (before `Verikloak::Middleware`)
  - Tests for custom insertion positions (`bff_header_guard_insert_before`, `bff_header_guard_insert_after`)
  - Tests for disabled state (`auto_insert_bff_header_guard = false`)
  - Tests for undefined `HeaderGuard` scenarios

---

## [0.2.9] - 2025-12-31

### Fixed
- **BREAKING FIX**: Railtie initializer now runs `after: :load_config_initializers` to ensure
  `config/initializers/verikloak.rb` settings are applied before middleware insertion
  - Previously, the initializer ran before `load_config_initializers`, causing settings in
    `config/initializers/*.rb` to be ignored
  - This was particularly problematic in Rails 8.x where initialization order is stricter

### Changed
- **Dependency**: Now requires `verikloak >= 0.3.0` (was `>= 0.2.0`)
  - This is necessary because the `issuer` parameter in `middleware_options` is now supported
    by verikloak 0.3.0+

### Migration Guide

If you were using the workaround of placing Verikloak configuration in `config/application.rb`,
you can now move it back to `config/initializers/verikloak.rb`:

```ruby
# config/initializers/verikloak.rb (now works correctly)
Rails.application.configure do
  config.verikloak.discovery_url = ENV['KEYCLOAK_DISCOVERY_URL']
  config.verikloak.audience = ENV['KEYCLOAK_AUDIENCE']
  config.verikloak.issuer = ENV['KEYCLOAK_ISSUER']
end
```

## [0.2.8] - 2025-10-03

### Changed
- Refactor controller helpers to use shared `_verikloak_fetch_request_context` method for consistent RequestStore fallback handling
- Optimize configuration access by caching `Verikloak::Rails.config` in log tag building
- Extract `auth_headers` method in ErrorRenderer for reusable WWW-Authenticate header generation
- Streamline middleware configuration by inlining BFF guard insertion into main configuration flow
- Improve middleware insertion error handling with `try_insert_after` and `warn_with_fallback` utilities

### Added
- Support for advanced middleware options: `token_verify_options`, `decoder_cache_limit`, `token_env_key`, `user_env_key`
- `bff_header_guard_options` configuration for verikloak-bff library integration
- Centralized `CONFIG_KEYS` constant in Railtie for consistent configuration management
- Enhanced README documentation with RequestStore vs Rack environment priority examples

### Fixed
- Only call `configure_bff_guard` when middleware stack is successfully created
- Replace `each_with_object` with `transform_keys` for better Ruby style compliance

## [0.2.7] - 2025-09-23

### Fixed
- Handle `RuntimeError` exceptions from `ActionDispatch::MiddlewareStack#insert_after` in Rails 8+
- Add `inserted` flag to prevent duplicate middleware insertion when fallback is used
- Enhance error handling to gracefully handle all middleware insertion failures

### Changed
- Update middleware insertion candidates logic for better Rails version compatibility
  - Rails 8+ now raises `RuntimeError` instead of the deprecated `ActionDispatch::MiddlewareStack::MiddlewareNotFound`
  - Broaden exception handling to catch `StandardError` for robustness across Rails versions
  - Improve logging and debugging information for middleware insertion failures

## [0.2.6] - 2025-09-23

### Fixed
- Leave `config.verikloak.rescue_pundit` commented in the installer initializer so `verikloak-pundit` can automatically disable the built-in rescue.

### Documentation
- Align README compatibility with the current `verikloak` dependency range.
- Clarify how the Pundit rescue interacts with the optional `verikloak-pundit` gem and adjust examples accordingly.

## [0.2.5] - 2025-09-23

### Added
- Integration test coverage for missing discovery URL scenarios
- `reset!` method for configuration cleanup in test environments

### Fixed
- Graceful handling of missing or blank discovery URLs during middleware configuration
- Skip middleware insertion and log warning when discovery URL is not configured
- Only configure BFF header guard when base middleware is successfully inserted

### Changed
- Improved error handling and validation for discovery URL configuration
- Enhanced middleware insertion logic with better separation of concerns

## [0.2.4] - 2025-09-23

### Fixed
- Package the installer template so `rails g verikloak:install` works in packaged gems (no more missing `initializer.rb.erb`).

## [0.2.3] - 2025-09-22

### Changed
- Provide a safe default audience (`'rails-api'`) so fresh installs keep `Verikloak::Middleware` active and remain compatible with the optional `verikloak-audience` gem.

## [0.2.2] - 2025-09-21

### Added
- Automatically insert `Verikloak::Bff::HeaderGuard` when the optional gem is available, with configuration toggles and ordering controls.
- Configuration knobs for positioning the base `Verikloak::Middleware` within the Rack stack.

### Changed
- Disable the built-in Pundit rescue when `verikloak-pundit` is loaded unless explicitly configured.

### Documentation
- Note related gems in the installer output and README, including new configuration options for middleware ordering and BFF auto-insertion.

## [0.2.1] - 2025-09-21

### Changed
- Simplify `with_required_audience!` to always raise `Verikloak::Error`, letting the shared handler render forbidden responses

### Fixed
- Ensure the 500 JSON renderer logs exceptions against the actual Rails logger even when wrapped by tagged logging adapters

### Documentation
- Describe the `rescue_pundit` configuration flag and default initializer settings

## [0.2.0] - 2025-09-14

### Breaking
- Extracted BFF-related functionality into a separate gem, "verikloak-bff". This gem no longer ships BFF-specific middleware or configuration

### Removed
- Middleware `Verikloak::Rails::MiddlewareIntegration::ForwardedAccessToken`
- Configuration keys: `config.verikloak.trust_forwarded_access_token`, `config.verikloak.trusted_proxy_subnets`, `config.verikloak.token_header_priority`
- Corresponding entries in the installer initializer template
- BFF-related sections in README and related unit/integration specs

### Migration
1. Add `gem 'verikloak-bff'` to your application Gemfile and bundle
2. Create an initializer (e.g., `config/initializers/verikloak_bff.rb`) and configure `Verikloak::BFF` (e.g., `trusted_proxies`, header/claims consistency)
3. Insert the BFF middleware before the core `Verikloak::Middleware`:
   ```ruby
   config.middleware.insert_before Verikloak::Middleware, Verikloak::BFF::HeaderGuard
   ```
4. Remove any old `config.verikloak.*` BFF options from your app config; they are no longer used by this gem

Reference: verikloak-bff https://github.com/taiyaky/verikloak-bff (Rails guide: `docs/rails.md`)

## [0.1.1] - 2025-09-13

### Fixed
- ForwardedAccessToken: fix `ensure_bearer` accepting malformed values (e.g., `BearerXYZ`)

### Changed
- Strengthen Bearer scheme normalization to always produce `Bearer <token>`
  - Detect scheme case-insensitively
  - Collapse tabs/multiple spaces after the scheme to a single space
  - Normalize missing-space form `BearerXYZ` to `Bearer XYZ`
- Add/update middleware specs to cover the above normalization

## [0.1.0] - 2025-09-07

### Added
- Initial release of `verikloak-rails` (Rails integration for Verikloak)
- Railtie auto-wiring via `config.verikloak.*` and installer generator `rails g verikloak:install`
- Controller concern with authentication helpers:
  - `before_action :authenticate_user!`
  - `current_user_claims`, `current_subject`, `current_token`, `authenticated?`, `with_required_audience!`
- Rack middleware integration:
  - Auto-inserts `Verikloak::Rails::MiddlewareIntegration::ForwardedAccessToken` and base `Verikloak::Middleware`
  - Optional BFF header promotion from `X-Forwarded-Access-Token` to `Authorization`, gated by `trust_forwarded_access_token` and `trusted_proxy_subnets` (never overwrites existing `Authorization`)
  - Token sourcing priority configurable via `token_header_priority`
- Consistent JSON error responses and statuses:
  - 401/403/503 standardized; `WWW-Authenticate` header on 401
  - Optional global 500 JSON via `config.verikloak.render_500_json`
- Optional Pundit integration: rescue `Pundit::NotAuthorizedError` to 403 JSON (`config.verikloak.rescue_pundit`)
- Request logging tags (`:request_id`, `:sub`) via `config.verikloak.logger_tags`
- Configurable initializer: `discovery_url`, `audience`, `issuer`, `leeway`, `skip_paths`, `trust_forwarded_access_token`, `trusted_proxy_subnets`, `auto_include_controller`, `error_renderer`, and more
- Compatibility: Ruby >= 3.1, Rails 6.1–8.x; depends on `verikloak` >= 0.1.2, < 0.2
