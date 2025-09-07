# verikloak-rails

Rails integration for Verikloak.

## Purpose
Provide near-zero-ceremony authentication for Rails with consistent JSON errors and sensible defaults.

## Features
- Auto-wiring via Railtie (`config.verikloak.*`)
- Controller concern with `before_action :authenticate_user!`
- Helpers: `current_user_claims`, `current_subject`, `current_token`, `authenticated?`
- Exceptions → standardized JSON (401/403/503) with `WWW-Authenticate` on 401
- Log tagging (`request_id`, `sub`)
- Installer generator: `rails g verikloak:install`

## Compatibility
- Ruby: >= 3.4
- Rails: 6.1 – 8.x
- verikloak: 0.1.x

## Quick Start
```bash
bundle add verikloak verikloak-rails
rails g verikloak:install
```

Then configure `config/initializers/verikloak.rb`.

## Controller Helpers
### Available Methods
- `before_action :authenticate_user!`
- `current_user_claims`, `current_subject`, `current_token`, `authenticated?`
- `current_user_claims`/`current_token` prefer Rack env (`verikloak.user`, `verikloak.token`), and fall back to RequestStore (`:verikloak_user`, `:verikloak_token`) when present.
- Consistent JSON errors for 401/403/503 with `WWW-Authenticate` on 401

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

## Middleware
### Inserted Middlewares
Two middleware are auto-inserted:
- `Verikloak::Rails::MiddlewareIntegration::ForwardedAccessToken`
- `Verikloak::Middleware` (from base gem)

### BFF Header Promotion
When using BFF like oauth2-proxy, `X-Forwarded-Access-Token` can be promoted to `Authorization` if enabled and the direct peer IP is trusted.

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
| `error_renderer` | callable | Override error rendering | built-in JSON renderer |
| `auto_include_controller` | Boolean | Auto-include controller concern | `true` |
| `render_500_json` | Boolean | Rescue `StandardError` and render JSON 500 | `false` |
| `token_header_priority` | Array<String> | Env header priority to source bearer token | `['HTTP_X_FORWARDED_ACCESS_TOKEN','HTTP_AUTHORIZATION']` |
| `rescue_pundit` | Boolean | Rescue `Pundit::NotAuthorizedError` to 403 JSON when Pundit is present | `true` |

Environment variable examples are in the generated initializer.

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
- 401 Unauthorized: typically `invalid_token`, `unauthorized`. Includes `WWW-Authenticate: Bearer` with optional `error` and `error_description`.
- 403 Forbidden: audience checks via `with_required_audience!`, or `Pundit::NotAuthorizedError` when optional rescue is enabled.
- 503 Service Unavailable: infrastructure/metadata issues (e.g., JWKS/discovery fetch/parse failures).

### Customize
Customize rendering by assigning `config.verikloak.error_renderer`.

## Examples
### Initializer (selected options)
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

## Customization
### Custom Error Renderer
```ruby
class MyErrorRenderer
  def render(controller, error)
    controller.render json: { error: 'custom', message: error.message }, status: :unauthorized
  end
end

Rails.application.configure do
  config.verikloak.error_renderer = MyErrorRenderer.new
end
```

### Manual Include (disable auto-include)
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
- Verikloak (base gem): https://github.com/taiyaky/verikloak
- RubyGems: https://rubygems.org/gems/verikloak
