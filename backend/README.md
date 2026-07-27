# CodeVault tracked links backend

This directory contains a standalone Cloudflare Worker backed by D1. It creates opaque redirects for Apple offer-code redemption URLs and stores only aggregate interaction state. A `GET` to a redirect records first-seen time, last-seen time, and visit count. A `HEAD` request does not count.

The signal means that the redirect was requested. Mail scanners and preview bots can request links, so it does not prove a human tap or an App Store redemption.

## Local development

Requirements: Node.js 22 or newer and a Cloudflare account for deployment.

```sh
npm install
cp .dev.vars.example .dev.vars
npm run db:migrate:local
npm test
npm run check
npm run dev
```

`.dev.vars` and all `.dev.vars.*` variants are ignored. Never commit real management tokens, encryption keys, account IDs, D1 IDs, custom domains, or offer codes. The committed example values are synthetic and are not safe for deployment.

## API

All `/v1/*` requests require `Authorization: Bearer <token>`.

- `GET /v1/health`
- `POST /v1/links` with JSON `{ "clientId": "<OfferCode UUID>", "destinationURL": "https://apps.apple.com/redeem?...", "expiresAt": "<optional ISO 8601>" }` and `Idempotency-Key` equal to `clientId`
- `POST /v1/links/status` with JSON `{ "ids": ["<backend link UUID>"] }`, up to 100 IDs
- `GET /r/{slug}` records an aggregate visit and redirects
- `HEAD /r/{slug}` redirects without recording a visit

Registration returns `id`, `shortURL`, `createdAt`, and nullable `expiresAt`. Status lookup returns `links` containing `id`, nullable `firstSeenAt`, nullable `lastSeenAt`, and `visitCount`. All timestamps are UTC ISO 8601 strings.

Only HTTPS `apps.apple.com/redeem` destinations with numeric `id`, non-empty `code`, and optional `ctx=offercodes` parameters are accepted. Unknown and duplicate query parameters are rejected.

## Deployment

1. Authenticate Wrangler and create the database:

   ```sh
   npx wrangler login
   npx wrangler d1 create codevault-tracked-links
   ```

2. Copy the returned D1 database ID into `wrangler.toml`. Replace `PUBLIC_BASE_URL` with the HTTPS custom-domain origin. Keep `workers_dev = false` so deployment does not accidentally expose an unplanned `workers.dev` address.

3. Generate secrets locally. Use a unique management token of at least 32 characters and exactly 32 random bytes encoded as base64 for the encryption key. Store both through Wrangler prompts, never in `wrangler.toml`:

   ```sh
   npx wrangler secret put MANAGEMENT_API_TOKEN
   npx wrangler secret put DESTINATION_ENCRYPTION_KEY
   ```

4. Apply the migration before deploying:

   ```sh
   npm run db:migrate:remote
   npm run deploy
   ```

5. Configure the Worker custom domain in Cloudflare, then smoke-test authenticated health, registration, redirect, and batch status. The `PUBLIC_BASE_URL` origin must match that domain.

6. If the rate-limit namespace IDs conflict with bindings in the Cloudflare account, replace the synthetic `1001` and `1002` IDs with unused integer IDs before deployment.

Back up the D1 database before rotating `DESTINATION_ENCRYPTION_KEY`. Existing destinations cannot be decrypted after key rotation unless they are re-encrypted first.

## Privacy and operations

- Destination URLs are encrypted with AES-256-GCM. A SHA-256 digest is retained only to enforce idempotency.
- Slugs contain 128 random bits. Management link IDs and client IDs are separate UUIDs.
- No per-visit table exists. The Worker does not log destinations, codes, authorization headers, IP addresses, user agents, or referrers.
- Redirect rate-limit keys are opaque slugs. Registration uses one constant route key. Neither binding receives source metadata.
- Responses disable caching and apply restrictive browser security headers.
- Expired links return `410 Gone` without incrementing aggregate status.
