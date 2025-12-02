# Hack Club Submit – Agent Guide

## Commands
- **Dev**: `bin/dev` (runs Rails + Tailwind watcher with Foreman)
- **Test**: `bin/rails test` (run all tests) or `bin/rails test test/path/to/file_test.rb` (single test file)
- **Console**: `bin/rails console` (inspect data)
- **Database**: `bin/rails db:prepare` (setup), `bin/rails db:seed` (seed with superadmin)

## Architecture
- **Rails 7.1** app centered on OAuth with Hack Club Auth; entry point is `ProgramsController#show` (route: `/:program`)
- **Core controllers**: `IdentityController` (browser OAuth), `Api::VerifyController` (server verification), `Popup::AuthorizeController` (partner popup flow), `Admin::SessionsController` (admin login)
- **Key models**: `Program` (stores theming, scopes, mappings), `AuthorizedSubmitToken` (submit tokens), `AuthorizationRequest` (popup flow), `VerificationAttempt` (audit log), `AdminUser`, `UserJourneyEvent`
- **Services**: `StateToken` (OAuth state generation/validation), `IdentityNormalizer` (normalize identity payloads), `UserJourneyFlow` (journey helpers)
- **Database**: PostgreSQL; dev DB is `submit_ruby_development`, test DB is `submit_ruby_test`
- **Frontend**: Stimulus controllers in `app/javascript/controllers`, Tailwind via `tailwindcss-rails`, SVGs via `inline_svg` (store in `app/assets/images`)

## Conventions & Patterns
- **URL joining**: Use `ApplicationController#join_url`, never `File.join` for URLs
- **State tokens**: Generate with `StateToken.generate`, validate with `StateToken.verify`
- **Identity normalization**: Always call `IdentityNormalizer.normalize` before using identity payloads
- **Field filtering**: Respect `Program#allowed_identity_fields` when returning identity data (see `Api::VerifyController` for examples)
- **Token consumption**: Use `AuthorizedSubmitToken#consume!` to mark tokens used; reuse returns 410
- **Journey logging**: Log flow steps with `UserJourneyEvent.create! rescue nil` (pattern: `event_type='program_page'`)
- **Colors**: `Program` stores hex colors without `#`; callbacks downcase them automatically
- **Error handling**: Use `create_attempt_safely!` for `VerificationAttempt` to avoid unique constraint violations
- **External redirects**: Require `allow_other_host: true` (configured globally via `permit_other_host_redirects.rb`)
