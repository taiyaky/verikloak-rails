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
- verikloak: >= 0.1.2, < 0.2

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
| `with_required_audience!(*aud)` | Enforce that `aud` includes all required entries | `void` | Renders standardized 403 JSON when requirements are not met |

### Data Sources
| Value | Rack env keys | Fallback (RequestStore) | Notes |
| --- | --- | --- | --- |
| `current_user_claims` | `verikloak.user` | `:verikloak_user` | Uses RequestStore only when available |
| `current_token` | `verikloak.token` | `:verikloak_token` | Uses RequestStore only when available |

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

## Middleware
### Inserted Middlewares
| Component | Inserted after | Purpose |
| --- | --- | --- |
| `Verikloak::Rails::MiddlewareIntegration::ForwardedAccessToken` | `Rails::Rack::Logger` | Promote trusted `X-Forwarded-Access-Token` to `Authorization` and, when `Authorization` is empty, set it from a prioritized list of headers |
| `Verikloak::Middleware` | `ForwardedAccessToken` | Validate Bearer JWT (OIDC discovery + JWKS), set `verikloak.user`/`verikloak.token`, and honor `skip_paths` |

### Header Sources and Trust
- Never overwrites an existing `Authorization` header.
- Considers `X-Forwarded-Access-Token` only when both are true: `config.verikloak.trust_forwarded_access_token` is enabled and the direct peer IP is within `config.verikloak.trusted_proxy_subnets`.
- `config.verikloak.token_header_priority` decides which env header can seed `Authorization` when it is empty. Note: `HTTP_AUTHORIZATION` is ignored as a source (it is the target header); include other headers if you need additional sources. Forwarded headers are skipped if not trusted.
- Direct peer detection prefers `REMOTE_ADDR`, falling back to the nearest proxy in `X-Forwarded-For` when needed.

### BFF Header Promotion
When fronted by a BFF (e.g., oauth2-proxy) that injects `X-Forwarded-Access-Token`, you can promote that header to `Authorization` from trusted sources only.

Enable promotion and restrict to trusted subnets:

```ruby
Rails.application.configure do
  config.verikloak.trust_forwarded_access_token = true
  config.verikloak.trusted_proxy_subnets = [
    '10.0.0.0/8',
    '192.168.0.0/16'
  ]
end
```

### Reordering or Disabling (advanced)
You can adjust the stack in an initializer after the gem loads, for example:

```ruby
Rails.application.configure do
  # Remove header-promotion middleware if you never use BFF tokens
  config.middleware.delete Verikloak::Rails::MiddlewareIntegration::ForwardedAccessToken

  # Or move the middleware earlier/later if your stack requires it
  # config.middleware.insert_before SomeOtherMiddleware, Verikloak::Rails::MiddlewareIntegration::ForwardedAccessToken,
  #   trust_forwarded: Verikloak::Rails.config.trust_forwarded_access_token,
  #   trusted_proxies: Verikloak::Rails.config.trusted_proxy_subnets,
  #   header_priority: Verikloak::Rails.config.token_header_priority
end
```

## Configuration (initializer)
### Keys
Keys under `config.verikloak`:

| Key | Type | Description | Default |
| --- | --- | --- | --- |
| `discovery_url` | String | OIDC discovery URL | `nil` |
| `audience` | String or Array | Expected `aud` | `nil` |
| `issuer` | String | Expected `iss` | `nil` |
| `leeway` | Integer | Clock skew allowance (seconds) | `60` |
| `skip_paths` | Array<String> | Paths to skip verification | `['/up','/health','/rails/health']` |
| `trust_forwarded_access_token` | Boolean | Trust `X-Forwarded-Access-Token` from trusted proxies | `false` |
| `trusted_proxy_subnets` | Array<String or IPAddr> | Subnets allowed to be treated as trusted | `[]` (treat all as trusted; set explicit ranges in production) |
| `logger_tags` | Array<Symbol> | Tags to add to Rails logs. Supports `:request_id`, `:sub` | `[:request_id, :sub]` |
| `error_renderer` | Object responding to `render(controller, error)` | Override error rendering | built-in JSON renderer |
| `auto_include_controller` | Boolean | Auto-include controller concern | `true` |
| `render_500_json` | Boolean | Rescue `StandardError` and render JSON 500 | `false` |
| `token_header_priority` | Array<String> | Env header priority to source bearer token | `['HTTP_X_FORWARDED_ACCESS_TOKEN','HTTP_AUTHORIZATION']` |
| `rescue_pundit` | Boolean | Rescue `Pundit::NotAuthorizedError` to 403 JSON when Pundit is present | `true` |

Environment variable examples are in the generated initializer.

### Minimum Setup
- Required: set `discovery_url` to your provider’s OIDC discovery document URL.
- Recommended: set `audience` (expected `aud`), and `issuer` when known.
- Optional: enable BFF header promotion only with explicit `trusted_proxy_subnets`.

```ruby
# config/initializers/verikloak.rb
Rails.application.configure do
  config.verikloak.discovery_url = ENV['KEYCLOAK_DISCOVERY_URL']
  config.verikloak.audience      = ENV.fetch('VERIKLOAK_AUDIENCE', 'rails-api')
  # Optional but recommended when you know it
  # config.verikloak.issuer        = 'https://idp.example.com/realms/myrealm'

  # Leave header promotion off unless you run a trusted BFF/proxy
  # config.verikloak.trust_forwarded_access_token = false
  # config.verikloak.trusted_proxy_subnets = ['10.0.0.0/8']
end
```

Notes:
- For array-like values (`audience`, `skip_paths`, `trusted_proxy_subnets`, `token_header_priority`), prefer defining Ruby arrays in the initializer. If passing via ENV, use comma-separated strings and parse in the initializer.
- Header sourcing/trust behavior is described in “Middleware → Header Sources and Trust”.

### Full Example (selected options)
```ruby
# config/initializers/verikloak.rb
Rails.application.configure do
  config.verikloak.discovery_url = ENV['KEYCLOAK_DISCOVERY_URL']
  config.verikloak.audience      = ENV.fetch('VERIKLOAK_AUDIENCE', 'rails-api')
  config.verikloak.leeway        = Integer(ENV.fetch('VERIKLOAK_LEEWAY', '60'))
  config.verikloak.skip_paths    = %w[/up /health /rails/health]

  # Enable BFF header promotion only from trusted subnets
  config.verikloak.trust_forwarded_access_token = ENV.fetch('VERIKLOAK_TRUST_FWD_TOKEN', 'false') == 'true'
  config.verikloak.trusted_proxy_subnets = [
    '10.0.0.0/8', # internal LB
    # '192.168.0.0/16'
  ]

  config.verikloak.logger_tags = %i[request_id sub]
  config.verikloak.render_500_json = ENV.fetch('VERIKLOAK_RENDER_500', 'false') == 'true'
  config.verikloak.token_header_priority = %w[HTTP_X_FORWARDED_ACCESS_TOKEN HTTP_AUTHORIZATION]

  # Optional Pundit rescue (403 JSON)
  config.verikloak.rescue_pundit = ENV.fetch('VERIKLOAK_RESCUE_PUNDIT', 'true') == 'true'
end
```

### ENV Mapping

| Key | ENV var |
| --- | --- |
| `discovery_url` | `KEYCLOAK_DISCOVERY_URL` |
| `audience` | `VERIKLOAK_AUDIENCE` |
| `issuer` | `VERIKLOAK_ISSUER` |
| `leeway` | `VERIKLOAK_LEEWAY` |
| `trust_forwarded_access_token` | `VERIKLOAK_TRUST_FWD_TOKEN` |
| `render_500_json` | `VERIKLOAK_RENDER_500` |
| `rescue_pundit` | `VERIKLOAK_RESCUE_PUNDIT` |

### Notes
- Default for `trust_forwarded_access_token` is secure (`false`). Set `trusted_proxy_subnets` before enabling.
- The middleware never overwrites an existing `Authorization` header.
- If `trusted_proxy_subnets` is empty, all peers are treated as trusted. In production, set explicit subnets or keep `trust_forwarded_access_token` disabled.

## Errors
This gem standardizes JSON error responses and HTTP statuses. See [ERRORS.md](ERRORS.md) for details and examples.

### Statuses
| Status | Typical code(s) | When | Headers | Body (example) |
| --- | --- | --- | --- | --- |
| 401 Unauthorized | `invalid_token`, `unauthorized` | Missing/invalid Bearer token; failed signature/expiry/issuer/audience checks | `WWW-Authenticate: Bearer` with optional `error` and `error_description` | `{ "error": "invalid_token", "message": "token expired" }` |
| 403 Forbidden | `forbidden` | Audience check failure via `with_required_audience!`; optionally `Pundit::NotAuthorizedError` when rescue is enabled | — | `{ "error": "forbidden", "message": "Required audience not satisfied" }` |
| 503 Service Unavailable | `jwks_fetch_failed`, `jwks_parse_failed`, `discovery_metadata_fetch_failed`, `discovery_metadata_invalid` | Upstream metadata/JWKS issues | — | `{ "error": "jwks_fetch_failed", "message": "..." }` |

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

Note: Always sanitize values placed into `WWW-Authenticate` header parameters to avoid header injection. For example:

```ruby
class CompactErrorRenderer
  private
  def sanitize_quoted(val)
    # Escape quotes/backslashes and strip CR/LF
    val.to_s.gsub(/(["\\])/) { |m| "\\#{m}" }.gsub(/[\r\n]/, ' ')
  end
end
```

## Optional Pundit Rescue
If the `pundit` gem is present, `Pundit::NotAuthorizedError` is rescued to a standardized 403 JSON. This is a lightweight convenience only; deeper Pundit integration (policies, helpers) is out of scope and can live in a separate plugin.

### Toggle
Toggle with `config.verikloak.rescue_pundit` (default: true). Environment example:

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
- Verikloak (base gem): https://github.com/taiyaky/verikloak
- Verikloak on RubyGems: https://rubygems.org/gems/verikloak
