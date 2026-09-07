# Pot Master

SwiftUI iOS app for home poker circles — local SwiftData first, Supabase for cloud sync.

## Verified environment

- **Xcode:** 26.5 (Build 17F42)
- **Simulator:** No iOS Simulator runtimes are installed yet. Install via **Xcode → Settings → Components → iOS 26.5 Simulator**, then run the app with ⌘R.

```bash
xcodebuild -version
xcrun simctl list devices available
```

## Project

| Setting | Value |
|---------|--------|
| Path | `~/Projects/PokerLeader/` |
| Target | `PokerLeader` |
| Display name | Pot Master |
| Bundle ID | `com.mathisgad.pokerleader` |
| Deployment | iOS 17.0+ |

## Open & run

1. In Terminal: `cd ~/Projects/PokerLeader && git checkout main && git pull origin main`
2. Open `~/Projects/PokerLeader/PokerLeader.xcodeproj` in Xcode.
3. Select an **iPhone** simulator (after installing the iOS platform).
4. Set your **Team** under Signing & Capabilities if building to a device.
5. Press **Run** (⌘R). Clean the build folder (⇧⌘K) if you already had the app installed, then run again so you pick up files added on `main`.

CLI build (once a simulator runtime exists):

```bash
cd ~/Projects/PokerLeader
xcodebuild -scheme PokerLeader -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## Structure

```
PokerLeader/
├── App/                 MainTabView, AppRouter
├── Core/                Models, SwiftData, services, theme
├── Repositories/        SessionRepository
├── Features/            Circles, Session, Settlement, History, Board, Profile
├── Components/          Shared UI
└── Assets.xcassets/
```

## What works now (local)

- **Circles** home with sample data (Uni Boys, London, Work)
- **Join a table** with the 6-character code or share link — no friend request needed — from the Circles tab, a circle's detail page, or the Table tab
- **Table** tab: the table you are at comes first — its code, Share, Edit, and **Open table** — with your buy-in, a join box, and any other tables underneath
- **Your tables** — hosted and joined tables, tap any one to edit its name, currency, or seat money
- **8-seat table** with a Play button after you save a buy-in and sit down — the table code sits next to the share button at the top, so you can read it out or tap it to copy without leaving the table
- **A real hand of hold'em** dealt by the app — two cards each, then the ante round, the flop, the turn, and the river, each asking you to bet, check, or fold
- **One card under the table** holds everything a hand asks of you: your two cards, what they add up to, whose turn it is, and the buttons
- **Add money** while the table is being played — a stack in a hand belongs to that hand, so the money waits beside it and joins your stack as soon as the hand settles
- **Buy in again** when you run out: the table says you have nothing left and offers the button, for however much you want, whatever you first sat down with
- **Showdown**: everyone still in turns their cards over, the best five-card hand is read out ("Full house, kings full of twos"), and the pot lands in the winner's money on the table. The next hand deals itself — nobody has to tap through.
- **New session → Live table** (+ buy-in only, no voice/type)
- **Final stacks → Confirmation → Settlement → WhatsApp share**
- **History**, **Leaderboard**, **You** settings tab
- **SwiftData** persistence on device/simulator

## Supabase (cloud sync)

1. Create a project at [supabase.com](https://supabase.com).
2. In **Authentication → Providers**, enable **Anonymous sign-ins**.
3. In **SQL Editor**, run the migration in `supabase/migrations/20250623000000_initial_schema.sql`.
4. Copy your project URL and anon key from **Project Settings → API**.
5. Duplicate `PokerLeader/Supabase.plist.example` as `PokerLeader/Supabase.plist` and paste your values:

```xml
<key>SUPABASE_URL</key>
<string>https://YOUR_PROJECT.supabase.co</string>
<key>SUPABASE_ANON_KEY</key>
<string>YOUR_ANON_KEY</string>
```

6. Build and run. The **You** tab shows **Cloud sync: Signed in** when configured and authenticated.

### Sign-in (required for cloud sync)

Enable these in Supabase **Authentication → Providers**:

- **Email** — for one-time passcode sign-in (edit the Magic Link email template to include `{{ .Token }}` so users receive a 6-digit code)
- **Apple** — for Sign in with Apple (add your Apple Services ID in Supabase; enable the capability in Xcode)
- **Google** — for Sign in with Google (create OAuth credentials in [Google Cloud Console](https://console.cloud.google.com/), add the client ID and secret in Supabase, and add `com.mathisgad.pokerleader://auth-callback` under **Authentication → URL Configuration → Redirect URLs**)

In Xcode, enable **Sign in with Apple** under **Signing & Capabilities** for the PokerLeader target (entitlements file included).

On a new device: sign in with the **same account**, and your circles, sessions, and friend requests pull automatically.

Run the second migration for faster circle pull:

`supabase/migrations/20250623120000_circle_members_user_index.sql`

Run the account deletion migration before release:

`supabase/migrations/20250625120000_delete_own_account.sql`

**Required for two-person table sharing.** If you see `Could not find the table 'public.open_tables' in the schema cache`, the live Supabase project is missing this table. In the Supabase dashboard open **SQL Editor**, paste the entire file, and click **Run**:

`supabase/migrations/20260904120000_open_tables.sql`

That creates `public.open_tables`, grants API access, adds an atomic seat-merge function so two phones cannot overwrite each other, and reloads PostgREST’s schema cache. Anyone signed in can then join from the share link or the 6-character table code — a friend request is not required.

The ante and the hand in progress — cards, board, pot, and whose turn it is — sync between players on the existing `open_tables` row. A dedicated pair of columns is optional:

`supabase/migrations/20260905090000_open_tables_preflop_hand.sql`

If those columns are not there yet, the app keeps the seats, ante and hand together in the `seats` JSON so every signed-in device sees the same pot.

**Important:** Do not commit `PokerLeader/Supabase.plist` — it contains your API key. After adding or editing it, use **Product → Clean Build Folder** (⇧⌘K), then run again so Xcode copies the file into the app.

Without `Supabase.plist`, the app still works locally with SwiftData only.

## Project structure

See [Docs/PROJECT_STRUCTURE.md](Docs/PROJECT_STRUCTURE.md) for the full folder map.

**Recently added:**
- `Repositories/CircleRepository.swift`
- `Core/Services/BadgeService.swift`
- `Core/Extensions/RelativeDateFormatting.swift`
- `Core/Supabase/SupabaseBootstrap.swift`, `SupabaseSyncService.swift`
- `ViewModels/SessionFlowViewModel.swift`
- `Features/Circles/CircleDetailView.swift`, `JoinCircleSheet.swift`
- `PokerLeaderTests/` (add test target in Xcode to enable)
