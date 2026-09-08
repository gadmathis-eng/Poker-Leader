# PokerLeader — Project structure

```
PokerLeader/
├── PokerLeaderApp.swift          App entry, SwiftData container, sample seed
├── App/
│   ├── MainTabView.swift         Tab bar (Circles, History, Board, You)
│   └── AppRouter.swift           Navigation routes & path state
├── Core/
│   ├── Models/                   SwiftData @Model types, shared table + hand, cards
│   ├── Persistence/              ModelContainer + sample data
│   ├── Services/                 Settlement, leaderboard, badges, WhatsApp text
│   │                             HandRound + PokerHandEvaluator are the local
│   │                             rules; the shared table uses the Postgres
│   │                             engine in 20260907200000_poker_server_engine.sql
│   │                             and 20260907210000_poker_engine_hardening.sql
│   │                             HandNarration puts the hand in front of you into words
│   ├── Theme/                    Colors, spacing
│   ├── Extensions/               Money + date formatting
│   ├── Vault/                    Player balances: integer-cents money, the
│   │                             backend seam, the Supabase and sandbox
│   │                             backends, and Apple Pay (PassKit sheet + mock)
│   └── Firebase/                 Placeholder until GoogleService-Info.plist
├── Repositories/
│   ├── CircleRepository.swift
│   └── SessionRepository.swift
├── ViewModels/
│   └── SessionFlowViewModel.swift
├── Features/
│   ├── Circles/
│   ├── Table/                    Shared table, seats, and playing a hand
│   ├── Session/
│   ├── Settlement/
│   ├── History/
│   ├── Leaderboard/
│   ├── Rivalry/
│   ├── Vault/                    Vault tab, Add Money, Cash Out, buy-in and
│   │                             leave-table settlement
│   └── Profile/
├── Components/                   Reusable SwiftUI
├── Resources/                    String catalog
└── Assets.xcassets/
```

## Data flow (local v1)

1. **SwiftData** stores circles, members, sessions, players, payments.
2. **Repositories** read/write the model context.
3. **Services** hold pure logic (settlement, leaderboard).
4. **Views** use `@Query` and repositories.

## Vault

Balances are the one thing the app does not own. Everything under `Core/Vault/`
asks a backend and reads the answer back; the ledger, the authorisation and the
arithmetic live in `supabase/migrations/20260907120000_vault_ledger.sql`. Stripe
charges the Apple Pay token from `supabase/functions/stripe-apple-pay` — see
[Payments.md](Payments.md). RevenueCat is not part of this path. See
[Vault.md](Vault.md).

## Firebase (phase 2)

Swap repository implementations for Firestore; keep services unchanged.
