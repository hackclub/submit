# Hack Club Submit

A lightweight Rails app that powers Hack Club's Submit flow. It handles OAuth with Hack Club Identity, issues short-lived tokens, and lets YSWS sites pre-fill forms with verified Identity Vault info.

## What you get

- Program landing pages that kick off the identity check.
- A `/api/identity/url` endpoint for building OAuth links.
- A `/api/verify` endpoint partners call to confirm a submission.

## Quick start

1. Install deps: `bundle install`.
2. Set up the database: `bin/rails db:prepare`.
3. Run everything with `bin/dev` (Procfile.dev).

Visit http://submit.hackclub.com via a program link, and walk through the flow.

## Configure it

Set these environment variables (shell, `.env`, or your process manager):
- `IDENTITY_URL`, `IDENTITY_CLIENT_ID`, `IDENTITY_CLIENT_SECRET`
- `IDENTITY_PROGRAM_KEY`
- `NEXTAUTH_URL`
- `SECRET_KEY_BASE`
- `DATABASE_URL` (production only)
- Optional: `STATE_HMAC_SECRET` (defaults to `SECRET_KEY_BASE`)

## Everyday commands

- `bin/rails server` — run just the Rails server.
- `bin/rails test` — run the test suite.
- `bin/rails console` — inspect data locally.

## How the flow works

1. Program pages seed a `submit_id` and log the visit.
2. Identity endpoints build OAuth state with `StateToken` and redirect to Hack Club Identity.
3. The callback fetches and normalizes identity via `IdentityNormalizer`, then redirects or issues a token.
4. Partners call `POST /api/verify` with that token to validate the submission.

## Deploying

Use the provided `Dockerfile` (see `bin/docker-entrypoint`) or your own Rails setup. Make sure `SECRET_KEY_BASE`, `DATABASE_URL`, and the identity environment variables are present before boot.

## Need more detail?

Check the models (`Program`, `AuthorizedSubmitToken`, `AuthorizationRequest`) and services (`IdentityNormalizer`, `StateToken`) for implementation notes. The `.github/copilot-instructions.md` file has deeper background if you need it.