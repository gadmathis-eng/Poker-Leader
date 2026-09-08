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
- **Join a table** on the Circles tab (top of the list) and on a circle's detail page
- **Table** tab: the table you are at comes first — its code, Share, Edit, and **Open table** — with your buy-in, a join box, and any other tables underneath
- **Your tables** — hosted and joined tables, tap any one to edit its name, currency, or seat money
- **8-seat table** with a Play button after you save a buy-in and sit down — the table code sits next to the share button at the top, so you can read it out or tap it to copy without leaving the table
- **A real hand of hold'em** dealt by the app — two cards each, then the ante round, the flop, the turn, and the river, each asking you to bet, check, or fold
- **Cards are dealt, not just shown** — the dealer pitches one card at a time from the middle of the felt, round the table and then round again, each card turning over in the air as it lands. The board is spread a street at a time into the slots waiting for it, and a hand shown down turns over where it lies
- **One card under the table** holds everything a hand asks of you: your two cards, what they add up to, whose turn it is, and the buttons
- **Add money** while a local table is being played — a stack in a hand belongs to that hand, so the money waits beside it and joins your stack as soon as the hand settles. Signed-in cloud tables keep the stack in the Vault, so extra chips are a new buy-in between hands, not a rewrite of the live pot.
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

That creates `public.open_tables`, grants API access, adds an atomic seat-merge function so two phones cannot overwrite each other, and reloads PostgREST’s schema cache. Friends can then join from the share link, or type the 6-character table code on the Table tab.

On a signed-in cloud table the server deals, takes every action, and settles the pot. Phones may request check, call, bet, raise, fold, all-in, start a hand, or leave — they cannot publish cards, the board, the pot, or a winner. A six-character table code is enough to preview who is sitting, not to watch the hand.

The older optional columns are unused once the engine migrations are applied:

`supabase/migrations/20260905090000_open_tables_preflop_hand.sql`

**Important:** Do not commit `PokerLeader/Supabase.plist` — it contains your API key. After adding or editing it, use **Product → Clean Build Folder** (⇧⌘K), then run again so Xcode copies the file into the app.

Without `Supabase.plist`, the app still works locally with SwiftData only.

## Vault (player balances)

The **Vault** is a player's private balance: money added, money on a table, and
money taken back out. It is on the **You** tab, under Settings → Vault.

**It is a labelled sandbox.** Deposits and payouts are still demo money. On an
iPhone with Wallet, Add Money opens the real Apple Pay sheet; the Vault still
credits demo funds until Stripe is connected. Simulator falls back to a test
authorization. Every screen showing a figure carries a
**Test Mode · Demo Funds** badge.

See [Docs/ApplePay.md](Docs/ApplePay.md) to open the sheet, and
[Docs/Payments.md](Docs/Payments.md) to charge it with Stripe (RevenueCat is
for a digital subscription, not the Vault).

Run these migrations before using it with cloud sync, in order:

`supabase/migrations/20260907120000_vault_ledger.sql`
`supabase/migrations/20260907180000_vault_security_hardening.sql`
`supabase/migrations/20260907190000_open_tables_lockdown.sql`
`supabase/migrations/20260907200000_poker_server_engine.sql`
`supabase/migrations/20260907210000_poker_engine_hardening.sql`
`supabase/migrations/20260907220000_vault_summary_currency.sql`
`supabase/migrations/20260907230000_vault_fx_conversion.sql`

That creates the double-entry ledger, the row-level security that keeps one
player's balance out of every other player's reach, the server poker engine,
and the functions the app calls. Without them — or without signing in — the
Vault falls back to a demo ledger running inside the app, which the Vault tab
says on screen.

What works: adding money through Apple Pay (real sheet on device, test
authorization on Simulator), buying into a table from the Vault or straight
through Apple Pay, chips tracking a hand, cashing off a table back into the
Vault, and requesting a mock cash-out. A player's balance is never visible to
anyone else — at a table, the only figure that crosses between players is the
chips in front of a seat.

See [Docs/Vault.md](Docs/Vault.md) for the ledger design, the privacy model, what
is deliberately not built yet, and what connecting a real payment provider takes.
See [Docs/ApplePay.md](Docs/ApplePay.md) to get the Apple Pay sheet to open.
See [Docs/Payments.md](Docs/Payments.md) to charge it with Stripe, and why
RevenueCat is the wrong tool for the Vault.

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
