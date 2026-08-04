# Local developer-role assignment

This is a local Firebase Admin utility. It does not use Firestore and it must never be bundled with the iOS app.

1. Both approved Google accounts must sign in to Stylezam once so Firebase creates their Auth users.
2. Download a Firebase service-account JSON file and keep it outside this repository.
3. Export `GOOGLE_APPLICATION_CREDENTIALS` with that file's absolute path.
4. Export `STYLEZAM_DEVELOPER_EMAILS` as a comma-separated allowlist of the two approved emails.
5. Run `npm install`, then `npm run grant-developer -- approved@example.com` once per approved account.
6. In Stylezam, sign out and back in or tap **Refresh developer access**.

The script preserves existing custom claims and adds `developer: true` and `plan: "developer"`. Never put the service-account JSON, its private key, or the Admin SDK inside the iOS target.
