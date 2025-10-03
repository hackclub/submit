# Hack Club Submit – Copilot instructions
## Overview
- Rails 7.1 app that mirrors the old Next.js Submit flow; root landing is `ProgramsController#show` keyed by slug (`/:program`) and everything pivots around OAuth with Hack Club Identity.
- Primary controllers: `app/controllers/identity_controller.rb` (browser OAuth), `app/controllers/api/verify_controller.rb` (server-side verification), and `app/controllers/popup/authorize_controller.rb` (partner popup flow).
- Reuse the helpers in `UserJourneyFlow` and `StateToken`; they already encode/validate OAuth state and map identity data onto third-party form URLs.

## Identity and verification flow
- `ProgramsController#show` seeds `session[:submit_id]` and logs a `UserJourneyEvent` (`event_type='program_page'`). Anything new that starts a flow should keep that logging pattern (`UserJourneyEvent.create! rescue nil`).
- `IdentityController#url` and `#start` gate on active `Program` records and call `StateToken.generate`; do not build redirect URIs with `File.join`, use `ApplicationController#join_url`.
- Store submit tokens in `AuthorizedSubmitToken` and consume them via `consume!` once verification completes; the API treats any reuse as a 410.
- Normalize identity payloads with `IdentityNormalizer.normalize` before using them; this collapses address arrays and guarantees `email`.
- Always respect `Program#allowed_identity_fields` when returning identity data to clients (see `Api::VerifyController` and popup callback for examples).

## Admin & popup specifics
- Admin login (`Admin::SessionsController`) also rides the Identity OAuth flow; state must include `purpose: 'admin_login'` and passes via `session[:admin_state_nonce]`.
- `AuthorizationRequest` backs the popup flow, storing `auth_id`, status, and restricted `identity_response`; mark `consumed_at` when responding to `/api/authorize/:auth_id/status`.
- Popup OAuth state includes `auth_id`; `popup/authorize#callback` both completes the record and issues a fresh `AuthorizedSubmitToken` for downstream verification.

## Data & persistence
- Database is Postgres (`config/database.yml`), migrations live in `db/migrate`; `db/seeds.rb` creates a default superadmin (`leow@hackclub.com`).
- `Program` records hold theming hex values without `#`; callbacks downcase each color and `is_bg_primary_dark?` drives view contrast.
- `VerificationAttempt` captures every `/api/verify` call; reuse `create_attempt_safely!` to avoid breaking the unique `submit_id` constraint.
- When exposing identity data, always slice to approved fields before persisting or returning JSON (see `filtered_identity`).

## Frontend
- Stimulus controllers live in `app/javascript/controllers`; `verification_controller.js` owns the "Continue" button and expects `data-verification-program-slug-value`.
- Tailwind is managed via `tailwindcss-rails`; theme overrides are in `app/assets/tailwind/application.css` using `@theme` tokens consumed by ERB inline styles.
- SVGs are rendered with `inline_svg` helpers; store new assets under `app/assets/images` and reference them without `.svg`.

## Local dev workflow
- Run `bin/dev` (Foreman) to launch Rails + `tailwindcss:watch`; it enables `hotwire-livereload` for Stimulus/Turbo reloads.
- Environment variables required for the identity flow: `IDENTITY_URL`, `IDENTITY_CLIENT_ID`, `IDENTITY_CLIENT_SECRET`, `IDENTITY_PROGRAM_KEY`, `NEXTAUTH_URL`; set `STATE_HMAC_SECRET` to avoid falling back to `secret_key_base`.
- Prepare the database with `bin/rails db:prepare` and seed via `bin/rails db:seed`; tests (currently minimal) run with `bin/rails test` and expect a Postgres `submit_ruby_test` database.
- Docker deploy uses Thruster (`bin/thrust`) and the `bin/docker-entrypoint` script; it can run migrations in the background (`RUN_MIGRATIONS=before` forces blocking).

## Security & ops
- Rate limiting is centralized in `config/initializers/rack_attack.rb`; consider ceiling values before adding new endpoints.
- Requests time out after `REQUEST_TIMEOUT` seconds via `rack-timeout`; long-running actions should be avoided.
- Redirects to external hosts require `allow_other_host: true`; this is already configured globally by `permit_other_host_redirects.rb`.
- Observability hooks: Sentry is wired via `config/initializers/sentry.rb`, and HelpScout Beacon is conditionally injected when `HELPSCOUT_BEACON_ID` is present.
