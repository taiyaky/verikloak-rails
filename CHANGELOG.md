# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

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
