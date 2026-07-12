# PokerLeader — Project structure

```
PokerLeader/
├── PokerLeaderApp.swift          App entry, SwiftData container, sample seed
├── App/
│   ├── MainTabView.swift         Tab bar (Circles, History, Board, You)
│   └── AppRouter.swift           Navigation routes & path state
├── Core/
│   ├── Models/                   SwiftData @Model types
│   ├── Persistence/              ModelContainer + sample data
│   ├── Services/                 Settlement, leaderboard, badges, WhatsApp text
│   ├── Theme/                    Colors, spacing
│   ├── Extensions/               Money + date formatting
│   └── Firebase/                 Placeholder until GoogleService-Info.plist
├── Repositories/
│   ├── CircleRepository.swift
│   └── SessionRepository.swift
├── ViewModels/
│   └── SessionFlowViewModel.swift
├── Features/
│   ├── Circles/
│   ├── Session/
│   ├── Settlement/
│   ├── History/
│   ├── Leaderboard/
│   ├── Rivalry/
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

## Firebase (phase 2)

Swap repository implementations for Firestore; keep services unchanged.
