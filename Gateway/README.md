# Stylezam credential gateway

This optional, stateless Cloudflare Worker keeps shared Fireworks and YouCam
credentials out of a public iOS build. It is not used by the current hackathon
build, so adding or deploying it cannot change local scanning, search, or try-on.

The gateway accepts only signed-in Firebase users, verifies each Firebase ID
token with Google's Identity Toolkit, applies a small per-user rate limit, and
proxies only explicitly allowlisted Fireworks and YouCam operations. It has no
database, photo storage dependency, or generic upstream URL parameter.

Configure Worker secrets rather than committing values:

```sh
npx wrangler secret put FIREBASE_WEB_API_KEY
npx wrangler secret put FIREWORKS_API_KEY
npx wrangler secret put YOUCAM_API_KEY
```

Create a KV namespace for `RATE_LIMITS`, replace its ID in `wrangler.jsonc`,
then deploy with `npx wrangler deploy`. Before a public release, connect the iOS
network clients to the deployed HTTPS URL and add Firebase App Check/App Attest
in addition to Firebase Authentication. The direct `.env`/Keychain path remains
debug-only and must not be used in an App Store archive.
