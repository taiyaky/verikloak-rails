# verikloak-rails

[![CI](https://github.com/taiyaky/verikloak-rails/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/taiyaky/verikloak-rails/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/verikloak-rails)](https://rubygems.org/gems/verikloak-rails)
![Ruby Version](https://img.shields.io/badge/ruby-%3E%3D%203.1-blue)
[![Downloads](https://img.shields.io/gem/dt/verikloak-rails)](https://rubygems.org/gems/verikloak-rails)

Rails integration for Verikloak.

## Purpose
Provide drop-in, token-based authentication for Rails APIs via Verikloak (OIDC discovery and JWKS verification). It installs middleware and a controller concern to authenticate Bearer tokens, exposes helpers for claims and subject, and returns standardized JSON error responses (401/403/503) with `WWW-Authenticate` on 401. Defaults prioritize security while keeping configuration minimal.

## Features
- Auto-wiring via Railtie (`config.verikloak.*`)
- Controller concern with `before_action :authenticate_user!`
- Helpers: `current_user_claims`, `current_subject`, `current_token`, `authenticated?`
- Exceptions → standardized JSON (401/403/503) with `WWW-Authenticate` on 401
- Log tagging (`request_id`, `sub`)
- Installer generator: `rails g verikloak:install`

## Compatibility
- Ruby: >= 3.1
- Rails: 6.1 – 8.x
- verikloak: ~> 1.0

## Quick Start
```bash
bundle add verikloak verikloak-rails
rails g verikloak:install
```

Then configure `config/initializers/verikloak.rb`.

## Controller Helpers
### Available Methods
| Method | Purpose | Returns | On failure |
| --- | --- | --- | --- |
| `authenticate_user!` | Use as a `before_action` to require a valid Bearer token | `void` | Renders standardized 401 JSON and sets `WWW-Authenticate: Bearer` when token is absent/invalid |
| `authenticated?` | Whether verified user claims are present | `Boolean` | — |
| `current_user_claims` | Verified JWT claims (string keys) | `Hash` or `nil` | — |
| `current_subject` | Convenience accessor for `sub` claim | `String` or `nil` | — |
| `current_token` | Raw Bearer token from the request | `String` or `nil` | — |
| `with_required_audience!(*aud)` | Enforce that `aud` includes all required entries | `void` | Raises `Verikloak::Error('forbidden')` so the concern renders standardized 403 JSON and halts the action |

### Data Sources
| Value | Rack env keys | Fallback (RequestStore) | Notes |
| --- | --- | --- | --- |
| `current_user_claims` | `verikloak.user` | `:verikloak_user` | Uses RequestStore only when available |
| `current_token` | `verikloak.token` | `:verikloak_token` | Uses RequestStore only when available |

#### Priority and Behavior Details

The helpers follow this priority order:

1. **Primary**: `request.env` (Rack environment) - Set directly by `Verikloak::Middleware`
2. **Fallback**: `RequestStore.store` (when available) - Thread-local storage for background jobs

**Examples:**

```ruby
# In a controller action (normal case)
current_user_claims  # reads from request.env['verikloak.user']
current_token        # reads from request.env['verikloak.token']

# In a background job triggered during request
# (when RequestStore gem is present and middleware has mirrored values)
current_user_claims  # falls back to RequestStore.store[:verikloak_user]
current_token        # falls back to RequestStore.store[:verikloak_token]

# When RequestStore is not available or disabled
current_user_claims  # returns nil if not in request.env
current_token        # returns nil if not in request.env
```

**Custom Environment Keys**: If you configure custom `token_env_key` or `user_env_key`,
the helpers automatically adapt to use those keys instead of the defaults.

### Example Controller

```ruby
class ApiController < ApplicationController
  # Auto-included by default; if disabled, add explicitly:
  # include Verikloak::Rails::Controller

  def me
    render json: { sub: current_subject, claims: current_user_claims }
  end

  def must_have_aud
    with_required_audience!('my-api')
    render json: { ok: true }
  end
end
```

### Manual Include (disable auto-include)
If you disable auto-inclusion of the controller concern, add it manually:

```ruby
# config/initializers/verikloak.rb
Rails.application.configure do
  config.verikloak.auto_include_controller = false
end

# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  include Verikloak::Rails::Controller
end
```

### API Mode Support
Both `ActionController::Base` and `ActionController::API` are supported. The controller concern is automatically included in both when `auto_include_controller` is enabled (default).

```ruby
# Works automatically with Rails API mode (rails new myapp --api)
class ApplicationController < ActionController::API
  # Verikloak::Rails::Controller is auto-included
end
```

## Middleware
### Inserted Middleware
| Component | Inserted relative to | Purpose |
| --- | --- | --- |
| `Verikloak::Bff::HeaderGuard` (optional) | Before `Verikloak::Middleware` by default when the gem is present | Normalize or enforce trusted proxy headers such as `X-Forwarded-Access-Token` |
| `Verikloak::Middleware` | After `Rails::Rack::Logger` by default (configurable) | Validate Bearer JWT (OIDC discovery + JWKS), set `verikloak.user`/`verikloak.token`, and honor `skip_paths` |

### BFF Integration
Support for BFF header handling (e.g., normalizing or enforcing `X-Forwarded-Access-Token`) now lives in a dedicated gem: verikloak-bff.
Note: verikloak-bff's `HeaderGuard` never overwrites an existing `Authorization` header.

- Gem: https://github.com/taiyaky/verikloak-bff
- Rails guide: `docs/rails.md` in that repository

When `verikloak-bff` is on the load path, `verikloak-rails` automatically inserts `Verikloak::Bff::HeaderGuard` before the base middleware so forwarded headers are normalized before verification. Control this via `config.verikloak.auto_insert_bff_header_guard` and the `bff_header_guard_insert_before/after` knobs.

Use verikloak-bff alongside this gem when you front Rails with a BFF/proxy such as oauth2-proxy and need to enforce trusted forwarding and header consistency.

Assign `config.verikloak.bff_header_guard_options` to customize the guard before
it is inserted. Provide either a Hash (merged via attribute writers) or a block/
callable that receives the `Verikloak::BFF.configure` object so you can set
advanced options such as trusted proxies, forwarded header names, or custom log
hooks directly from the Rails initializer.

## Configuration (initializer)
### Keys
Keys under `config.verikloak`:

| Key | Type | Description | Default |
| --- | --- | --- | --- |
| `discovery_url` | String | OIDC discovery URL | `nil` |
| `audience` | String or Array | Expected `aud` | `'rails-api'` |
| `issuer` | String | Expected `iss` | `nil` |
| `leeway` | Integer | Clock skew allowance (seconds) | `60` |
| `skip_paths` | Array<String> | Paths to skip verification | `['/up','/health','/rails/health']` |
| `logger_tags` | Array<Symbol> | Tags to add to Rails logs. Supports `:request_id`, `:sub` | `[:request_id, :sub]` |
| `error_renderer` | Object responding to `render(controller, error)` | Override error rendering | built-in JSON renderer |
| `auto_include_controller` | Boolean | Auto-include controller concern | `true` |
| `render_500_json` | Boolean | Rescue `StandardError`, log the exception, and render JSON 500 | `false` |
| `rescue_pundit` | Boolean | Rescue `Pundit::NotAuthorizedError` to 403 JSON when Pundit is present<br/>(auto-disabled when `verikloak-pundit` is loaded and the initializer leaves it unset) | `true` |
| `middleware_insert_before` | Object/String/Symbol | Insert `Verikloak::Middleware` before this Rack middleware | `nil` |
| `middleware_insert_after` | Object/String/Symbol | Insert `Verikloak::Middleware` after this Rack middleware (`Rails::Rack::Logger` when `nil`) | `nil` |
| `auto_insert_bff_header_guard` | Boolean | Auto insert `Verikloak::Bff::HeaderGuard` when the gem is present | `true` |
| `bff_header_guard_insert_before` | Object/String/Symbol | Insert the header guard before this middleware (`Verikloak::Middleware` when `nil`) | `nil` |
| `bff_header_guard_insert_after` | Object/String/Symbol | Insert the header guard after this middleware | `nil` |
| `token_verify_options` | Hash | Additional options forwarded to `Verikloak::TokenDecoder` (e.g. `{ verify_iat: false }`) | `{}` |
| `decoder_cache_limit` | Integer or nil | Overrides the cached decoder count before eviction | `nil` (verikloak default `128`) |
| `token_env_key` | String | Custom Rack env key that stores the Bearer token | `nil` (middleware default `verikloak.token`) |
| `user_env_key` | String | Custom Rack env key that stores decoded claims | `nil` (middleware default `verikloak.user`) |
| `bff_header_guard_options` | Hash or Proc | Forwarded to `Verikloak::BFF.configure` prior to middleware insertion | `{}` |
| `allow_http` | Boolean | Allow `http://` discovery URLs (forwarded to core middleware). **Only for development/test.** | `false` |

Environment variable examples are in the generated initializer.

### Minimum Setup
- Required: set `discovery_url` to your provider’s OIDC discovery document URL.
- Recommended: set `audience` (expected `aud`), and `issuer` when known.

```ruby
# config/initializers/verikloak.rb
Rails.application.configure do
  config.verikloak.discovery_url = ENV['KEYCLOAK_DISCOVERY_URL']
  config.verikloak.audience      = ENV.fetch('VERIKLOAK_AUDIENCE', 'rails-api')
  # Optional but recommended when you know it
  # config.verikloak.issuer        = 'https://idp.example.com/realms/myrealm'

  # For BFF/proxy header handling, see verikloak-bff (auto inserted when present)
  # To customize ordering:
  # config.verikloak.middleware_insert_before = Rack::Attack
  # config.verikloak.auto_insert_bff_header_guard = false
end
```

Notes:
- For array-like values (`audience`, `skip_paths`), prefer defining Ruby arrays in the initializer. If passing via ENV, use comma-separated strings and parse in the initializer.

### Full Example (selected options)
```ruby
# config/initializers/verikloak.rb
Rails.application.configure do
  config.verikloak.discovery_url = ENV['KEYCLOAK_DISCOVERY_URL']
  config.verikloak.audience      = ENV.fetch('VERIKLOAK_AUDIENCE', 'rails-api')
  config.verikloak.leeway        = Integer(ENV.fetch('VERIKLOAK_LEEWAY', '60'))
  config.verikloak.skip_paths    = %w[/up /health /rails/health]

  config.verikloak.logger_tags = %i[request_id sub]
  config.verikloak.render_500_json = ENV.fetch('VERIKLOAK_RENDER_500', 'false') == 'true'

  # Optional Pundit rescue (403 JSON). Leave commented if you use
  # verikloak-pundit so it can disable the built-in handler automatically.
  # config.verikloak.rescue_pundit = ENV.fetch('VERIKLOAK_RESCUE_PUNDIT', 'true') == 'true'
end
```

### ENV Mapping

| Key | ENV var |
| --- | --- |
| `discovery_url` | `KEYCLOAK_DISCOVERY_URL` |
| `audience` | `VERIKLOAK_AUDIENCE` |
| `issuer` | `VERIKLOAK_ISSUER` |
| `leeway` | `VERIKLOAK_LEEWAY` |
| `render_500_json` | `VERIKLOAK_RENDER_500` |
| `rescue_pundit` | `VERIKLOAK_RESCUE_PUNDIT` |


## Errors
This gem standardizes JSON error responses and HTTP statuses. See [ERRORS.md](ERRORS.md) for details and examples.

### Statuses
| Status | Typical code(s) | When | Headers | Body (example) |
| --- | --- | --- | --- | --- |
| 401 Unauthorized | `invalid_token`, `unauthorized` | Missing/invalid Bearer token; failed signature/expiry/issuer/audience checks | `WWW-Authenticate: Bearer` with optional `error` and `error_description` | `{ "error": "invalid_token", "message": "token expired" }` |
| 403 Forbidden | `forbidden` | Audience check failure via `with_required_audience!`; optionally `Pundit::NotAuthorizedError` when rescue is enabled | — | `{ "error": "forbidden", "message": "Required audience not satisfied" }` |
| 503 Service Unavailable | `jwks_fetch_failed`, `jwks_parse_failed`, `discovery_metadata_fetch_failed`, `discovery_metadata_invalid`, `invalid_discovery_url`, `discovery_redirect_error` | Upstream metadata/JWKS issues | — | `{ "error": "jwks_fetch_failed", "message": "..." }` |

### Customize
Customize rendering by assigning `config.verikloak.error_renderer`.

Example: return a compact JSON shape while preserving `WWW-Authenticate` for 401.

```ruby
class CompactErrorRenderer
  def render(controller, error)
    code = error.respond_to?(:code) ? error.code : 'unauthorized'
    message = error.message.to_s

    status = case code
             when 'forbidden' then 403
             when 'jwks_fetch_failed', 'jwks_parse_failed', 'discovery_metadata_fetch_failed', 'discovery_metadata_invalid' then 503
             else 401
             end

    if status == 401
      hdr = +'Bearer'
      hdr << %( error="#{sanitize_quoted(code)}") if code
      hdr << %( error_description="#{sanitize_quoted(message)}") if message && !message.empty?
      controller.response.set_header('WWW-Authenticate', hdr)
    end

    controller.render json: { code: code, msg: message }, status: status
  end
end

Rails.application.configure do
  config.verikloak.error_renderer = CompactErrorRenderer.new
end
```

Note: Always sanitize values placed into `WWW-Authenticate` header parameters to avoid header injection. You can use the shared helper from the core gem:

```ruby
class CompactErrorRenderer
  private
  def sanitize(val)
    # Delegates to core gem's sanitizer — escapes quotes/backslashes,
    # truncates at CRLF, and strips all control characters.
    Verikloak::ErrorResponse.sanitize_header_value(val)
  end
end
```

## Optional Pundit Rescue
If the `pundit` gem is present, `Pundit::NotAuthorizedError` is rescued to a standardized 403 JSON. This is a lightweight convenience only; deeper Pundit integration (policies, helpers) is out of scope and can live in a separate plugin.

When the optional [`verikloak-pundit`](https://github.com/taiyaky/verikloak-pundit) gem is loaded, the built-in rescue is automatically disabled to avoid double-handling errors—as long as the initializer leaves `config.verikloak.rescue_pundit` unset. Uncomment the initializer line (or set the value elsewhere) if you prefer different behavior.

### Toggle
Toggle with `config.verikloak.rescue_pundit` (default: true; leave unset to allow `verikloak-pundit` to disable it). Environment example:

```ruby
# config/initializers/verikloak.rb
Rails.application.configure do
  # Disable the built-in rescue if you handle Pundit errors yourself
  config.verikloak.rescue_pundit = ENV.fetch('VERIKLOAK_RESCUE_PUNDIT', 'true') == 'true'
end
```

### Behavior Example
```ruby
# When Pundit raises:
raise Pundit::NotAuthorizedError, 'forbidden'
# The concern rescues and renders:
# { error: 'forbidden', message: 'forbidden' } with status 403
```

## Rails 8.0/8.1 Timezone Note
Rails 8.0 shows a deprecation for the upcoming 8.1 change where `to_time` preserves the receiver timezone. This gem does not call `to_time`, but your app may. To opt in and silence the deprecation, set:
```ruby
# config/application.rb
module YourApp
  class Application < Rails::Application
    config.active_support.to_time_preserves_timezone = :zone
  end
end
```

## Development (for contributors)
Clone and install dependencies:

```bash
git clone https://github.com/taiyaky/verikloak-rails.git
cd verikloak-rails
bundle install
```
See **Testing** below to run specs and RuboCop. For releasing, see **Publishing**.

## Testing
All pull requests and pushes are automatically tested with [RSpec](https://rspec.info/) and [RuboCop](https://rubocop.org/) via GitHub Actions.
See the CI badge at the top for current build status.

To run the test suite locally:

```bash
docker compose run --rm dev rspec
docker compose run --rm dev rubocop -a
```

## Contributing
Bug reports and pull requests are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## Security
If you find a security vulnerability, please follow the instructions in [SECURITY.md](SECURITY.md).

## License
This project is licensed under the [MIT License](LICENSE).

## Publishing (for maintainers)
Gem release instructions are documented separately in [MAINTAINERS.md](MAINTAINERS.md).

## Changelog
See [CHANGELOG.md](CHANGELOG.md) for release history.

## References
- verikloak-rails (this gem): https://rubygems.org/gems/verikloak-rails
- verikloak-bff: https://rubygems.org/gems/verikloak-bff
- Verikloak (base gem): https://github.com/taiyaky/verikloak
- Verikloak on RubyGems: https://rubygems.org/gems/verikloak
