# App Store Metadata Draft

## Name

Pot Master

## Subtitle

Track home poker nights

## Description

Pot Master helps home poker groups run a clean cash game night. Create a circle, invite players with a code, track buy-ins during the session, enter final stacks, and calculate the simplest settlement payments at the end.

Cloud sync keeps your circles and sessions available across devices for invited players.

## Keywords

poker,tracker,cash game,buy in,settlement,leaderboard,home game

## Support URL

https://potmaster.app/support/

Deploy the `web/` folder — see `web/DEPLOY-potmaster.app.md`.

## Privacy Policy URL

https://potmaster.app/privacy/

Markdown source: `Docs/PrivacyPolicy.md`

## Review Notes

Pot Master uses Supabase for optional cloud sync (Sign in with Apple, Google, and email OTP). The app does not process real-money payments; settlement results are informational only.

Test account (if needed): create a circle locally without signing in, or sign in with a reviewer account you create in Supabase Auth.

Account deletion is available in Settings → Account → Delete account.

## Pre-submission checklist

- [x] Run Supabase migration `20250625120000_delete_own_account.sql`
- [ ] Deploy `web/` to **potmaster.app** (see `web/DEPLOY-potmaster.app.md`)
- [ ] Set up **support@potmaster.app** email forwarding
- [ ] Production `Supabase.plist` bundled in release builds
- [ ] Apple Sign In + Google OAuth configured in Supabase and Apple Developer
- [ ] Privacy policy and support pages live at public URLs
- [ ] App Store Connect screenshots, age rating, and export compliance completed
