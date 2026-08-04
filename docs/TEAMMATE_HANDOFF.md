# Teammate handoff

The safest handoff is a Git clone plus a small private configuration exchange.
Do not zip and send the entire working folder: ignored credentials inside that
folder would be included even though Git never tracks them.

## What your teammate receives through Git

Push the repository and have your teammate clone it. The repository contains:

- the Swift source, extensions, assets, and XcodeGen project definition;
- the bundled Core ML model and its integrity manifest;
- Firebase and provider configuration templates;
- build, device-install, model-verification, and Firebase claim scripts;
- architecture, privacy, validation, and setup documentation.

The model is already in the repository. Your teammate does not download a model
or run a laptop/server for local garment detection.

## What to send privately

If both developers use the same Firebase project, send this one file through a
private channel such as an encrypted password-manager item or an expiring file
link:

```text
App/Resources/GoogleService-Info.plist
```

This plist is Firebase client configuration, not a Firebase Admin credential,
but keeping it out of a public repository prevents accidental project mix-ups.
Your teammate places it at the same path after cloning.

Search-provider credentials are optional for camera detection. Prefer separate
developer keys with their own hard usage caps. If the team intentionally shares
the internal testing keys, transfer the values securely and have the teammate
create a local `.env` from `.env.example`:

```bash
cp .env.example .env
chmod 600 .env
```

Never paste real key values into GitHub issues, commits, README files, chat
screenshots, or Xcode build settings committed to the project.

## What not to send

Do **not** send any of these files:

- a Firebase Admin SDK service-account JSON key;
- Apple signing certificates (`.p12`), App Store Connect keys (`.p8`), or
  provisioning profiles;
- your `Config/Secrets.xcconfig` or an exported Apple private key;
- Derived Data, build products, `.venv`, or `node_modules`.

For Firebase administration, invite the teammate to the Firebase/Google Cloud
project with the least role they need. If they genuinely need Admin SDK access,
they should create and protect their own local credential rather than copying
yours.

## Teammate setup

1. Clone the repository and install Xcode 26 or newer.
2. Place the privately received `GoogleService-Info.plist` under
   `App/Resources/`.
3. Copy `Config/Firebase.local.xcconfig.example` to
   `Config/Firebase.local.xcconfig`, then paste the plist's
   `REVERSED_CLIENT_ID` into `GOOGLE_REVERSED_CLIENT_ID`.
4. Run `./scripts/generate_project.sh` and open `Stylezam.xcodeproj`.
5. Choose the teammate's own Apple Development Team. Do not share signing
   certificates just to make local testing work.
6. Run `./scripts/check.sh`, then build the `Stylezam` scheme on a simulator or
   connected iPhone.
7. If product-search testing is needed, create `.env` as described above. The
   install script stores provided keys in that iPhone's Keychain.

For command-line device installation with a different phone or team:

```bash
STYLEZAM_DEVICE_ID=THEIR_DEVICE_UDID \
STYLEZAM_DEVELOPMENT_TEAM=THEIR_TEAM_ID \
./scripts/install_on_device.sh
```

Google Sign-In must be enabled in Firebase Authentication. A Firebase user is
not a developer merely because their email looks familiar: Developer Debug and
unlimited internal usage require a signed `developer: true` custom claim. The
claim utility and instructions are under `tools/firebase-admin/` and
[`SETUP.md`](SETUP.md).

## Before pushing or sharing

Run these checks from the repository root:

```bash
git check-ignore -v \
  .env \
  App/Resources/GoogleService-Info.plist \
  Config/Firebase.local.xcconfig

git status --short
./scripts/check.sh
```

The first command must show ignore rules for every local configuration file.
Review `git status` before committing so visual artifacts and other large files
are included only when the team actually wants them.
