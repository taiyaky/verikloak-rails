This gem returns consistent JSON errors for authentication failures.

- 401 Unauthorized
  - `invalid_token`, `unauthorized`
  - Includes `WWW-Authenticate: Bearer` header with optional `error` and `error_description`.

- 403 Forbidden
  - Used by controller helpers (e.g., audience checks, optional Pundit integration).

- 503 Service Unavailable
  - `jwks_fetch_failed`, `jwks_parse_failed`, `discovery_metadata_fetch_failed`, `discovery_metadata_invalid`

You can override rendering by assigning a custom `config.verikloak.error_renderer`.
