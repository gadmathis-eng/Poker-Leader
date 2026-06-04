# Poker Tracker iOS SwiftUI Implementation Plan

## 1. Goal

Build an iPhone app for casual poker groups that tracks circles, players,
live buy-ins, final stacks, settlement payments, history, leaderboards,
head-to-head rivalries, and player profiles.

The attached UI/UX describes a 12-screen app flow:

1. Circles home
2. Session setup
3. Live table mode
4. Final stacks entry
5. Balanced confirmation
6. Mismatch confirmation
7. Results and settlement
8. WhatsApp-ready sharing
9. Session history
10. Leaderboard
11. Head-to-head comparison
12. Player profile

## 2. Platform and Tooling

Use Apple's current iOS development stack:

- Language: Swift
- UI framework: SwiftUI
- Persistence: SwiftData
- IDE: latest stable Xcode
- Simulator: latest available iOS iPhone simulator
- App target: iPhone
- Tests: unit tests and UI tests enabled

Recommended deployment target:

- iOS 18 or later for broader support
- iOS 26 or later if the app is only targeting the latest simulator/runtime

Important environment note:

- The iOS simulator requires macOS and Xcode.
- This repository can store the source code and documentation, but the app
  must be built and run on a Mac with Xcode installed.

## 3. High-Level App Architecture

Use a simple MVVM-style SwiftUI architecture:

- Models hold persisted app data.
- ViewModels prepare screen-specific state and actions.
- Services contain reusable business logic.
- Views are SwiftUI screens and components.

Recommended folder structure:

```text
PokerTracker/
  App/
    PokerTrackerApp.swift
    AppRouter.swift
    AppTab.swift

  Models/
    Circle.swift
    Player.swift
    PokerSession.swift
    BuyIn.swift
    FinalStack.swift
    SettlementPayment.swift
    PlayerResult.swift
    Badge.swift

  Services/
    SettlementCalculator.swift
    StatsCalculator.swift
    ShareMessageBuilder.swift
    CurrencyFormatter.swift
    SampleDataSeeder.swift

  ViewModels/
    CirclesHomeViewModel.swift
    SessionSetupViewModel.swift
    LiveTableViewModel.swift
    FinalStacksViewModel.swift
    ConfirmationViewModel.swift
    ResultsSettlementViewModel.swift
    HistoryViewModel.swift
    LeaderboardViewModel.swift
    HeadToHeadViewModel.swift
    PlayerProfileViewModel.swift

  Views/
    Shared/
      AppHeaderView.swift
      SectionLabelView.swift
      PlayerAvatarView.swift
      PrimaryButton.swift
      SecondaryButton.swift
      MoneyTextView.swift
      StatCardView.swift

    Circles/
      CirclesHomeView.swift
      CircleCardView.swift
      NewCircleView.swift

    Session/
      SessionSetupView.swift
      LiveTableView.swift
      FinalStacksView.swift
      ConfirmationView.swift
      ResultsSettlementView.swift
      WhatsAppReadyView.swift

    History/
      SessionHistoryView.swift
      SessionHistoryRowView.swift

    Leaderboard/
      LeaderboardView.swift
      LeaderboardRowView.swift

    Players/
      HeadToHeadView.swift
      PlayerProfileView.swift

  Tests/
    SettlementCalculatorTests.swift
    StatsCalculatorTests.swift
    ShareMessageBuilderTests.swift
```

## 4. Navigation Plan

Use a main `TabView` with four tabs:

1. Circles
2. History
3. Board
4. You

Use `NavigationStack` inside each tab.

Primary session flow:

```text
Circles Home
  -> Session Setup
    -> Live Table Mode
      -> Final Stacks
        -> Confirmation
          -> Results and Settlement
            -> WhatsApp Ready
```

Define a route enum for stack-based navigation:

```swift
enum AppRoute: Hashable {
    case sessionSetup(circleId: UUID?)
    case liveTable(sessionId: UUID)
    case finalStacks(sessionId: UUID)
    case confirmation(sessionId: UUID)
    case results(sessionId: UUID)
    case whatsAppReady(sessionId: UUID)
    case playerProfile(playerId: UUID)
    case headToHead(playerAId: UUID, playerBId: UUID)
}
```

## 5. Money Handling

Never store money as `Double`.

Store money as integer minor units:

```text
GBP 20.00 = 2000 pence
GBP 80.00 = 8000 pence
```

Create a shared formatter service:

```swift
struct CurrencyFormatter {
    func string(fromMinorUnits amount: Int, currencyCode: String) -> String
    func signedString(fromMinorUnits amount: Int, currencyCode: String) -> String
}
```

Display examples:

```text
+GBP 80
-GBP 50
GBP 350
```

The final UI can render the correct currency symbol, for example GBP as
the pound symbol, through `NumberFormatter` or Swift currency formatting.

## 6. Data Models

### Circle

Represents a poker group.

Fields:

- id
- name
- shortCode
- currencyCode
- currencySymbol
- standardBuyInMinorUnits
- createdAt
- players
- sessions

Example:

```text
Name: Uni Boys
Short code: UB
Currency: GBP
Standard buy-in: 2000
```

### Player

Represents a player inside a circle.

Fields:

- id
- name
- handle
- avatarInitial
- createdAt

Example:

```text
Name: Alex
Handle: alexplaysaces
Avatar initial: A
```

### PokerSession

Represents one poker game.

Fields:

- id
- title
- date
- status
- createdAt
- completedAt
- buyIns
- finalStacks
- settlementPayments

Statuses:

```swift
enum SessionStatus: String, Codable {
    case setup
    case live
    case enteringFinalStacks
    case balancedConfirmation
    case mismatchConfirmation
    case settled
}
```

### BuyIn

Represents a player's buy-in event.

Fields:

- id
- playerId
- amountMinorUnits
- createdAt

### FinalStack

Represents what a player left the table with.

Fields:

- id
- playerId
- amountOutMinorUnits

### SettlementPayment

Represents one required payment after the game.

Fields:

- id
- fromPlayerId
- toPlayerId
- amountMinorUnits

### PlayerResult

Non-persisted calculation model.

Fields:

- playerId
- amountInMinorUnits
- amountOutMinorUnits
- netMinorUnits

Formula:

```text
net = amountOut - amountIn
```

## 7. Shared UI Design System

Create reusable SwiftUI components before building the full screen flow.

Components:

- `AppHeaderView`
- `SectionLabelView`
- `PlayerAvatarView`
- `PrimaryButton`
- `SecondaryButton`
- `MoneyTextView`
- `StatCardView`
- `CircleCardView`
- `SessionHistoryRowView`
- `LeaderboardRowView`

Visual rules:

- Use uppercase section labels with increased letter spacing.
- Use circular initials for players.
- Use cards for circles, sessions, stats, and payments.
- Use green for positive net values.
- Use red for negative net values.
- Use orange/yellow for mismatch warnings.
- Use monospaced digits for money values.
- Support light and dark mode.
- Add accessibility labels to important controls and money values.

## 8. Screen Implementation Details

### 8.1 Circles Home

Purpose:

Show all poker circles and let the user start a new session.

UI content:

- Header: `CIRCLES - HOME`
- App title: `Poker Tracker`
- Section: `YOUR CIRCLES`
- Circle cards
- New circle button
- Start a session button
- Bottom tabs

Each circle card shows:

- Short code, for example `UB`
- Name, for example `Uni Boys`
- Member count
- Game count
- User net result
- Player initials
- Last played date

Acceptance criteria:

- Circles are listed from SwiftData.
- Positive user net is green.
- Negative user net is red.
- `New circle` opens circle creation.
- `Start a session` opens session setup.

### 8.2 New Circle

Purpose:

Create a poker group.

Fields:

- Circle name
- Short code
- Currency
- Standard buy-in
- Initial players

Validation:

- Circle name is required.
- Currency is required.
- Buy-in must be greater than zero.
- At least two players are required.

Acceptance criteria:

- New circle is saved.
- Players are saved with the circle.
- New circle appears on Circles Home.

### 8.3 Session Setup

Purpose:

Configure a new poker session.

UI content:

- Header: `SESSION SETUP`
- Circle selector
- Session title field
- Suggested session names
- Standard buy-in
- Currency
- Player selector
- Add player button
- Start session button

Suggested session names:

- Friday Night Poker
- The Monthly Robbery
- Boys Night Table
- Dan's Flat Game

Validation:

- Circle selected
- Session title is not empty
- At least two players selected
- Buy-in amount greater than zero

Acceptance criteria:

- Starting a session creates a `PokerSession`.
- Selected players are linked to the session.
- First standard buy-in may optionally be added for each player, depending
  on product decision.
- User is routed to Live Table Mode.

### 8.4 Live Table Mode

Purpose:

Track buy-ins while the game is running.

UI content:

- Header: `TABLE MODE - LIVE`
- Current pot
- Session title
- Buy-in instruction
- Total number of buy-ins
- Player rows
- Voice button
- Manual buy-in button
- End game button

MVP controls for each player:

- Avatar
- Name
- Buy-in count
- Total amount in
- Add buy-in button
- Optional remove/edit button

Calculations:

```text
playerAmountIn = sum(player buy-ins)
totalPot = sum(all buy-ins)
buyInCount = playerAmountIn / standardBuyIn
```

Acceptance criteria:

- Tapping add buy-in adds one standard buy-in.
- Pot updates immediately.
- Player buy-in count updates immediately.
- End game routes to Final Stacks.

Voice input:

- Defer until after MVP.
- The MVP may show a disabled or placeholder voice action.

### 8.5 Final Stacks

Purpose:

Enter what each player left with.

UI content:

- Header: `FINAL STACKS - MANUAL`
- Explainer text
- Player rows
- Each row shows amount in
- Each row has amount out input
- Pot check section
- Review settlement button

Calculations:

```text
totalIn = sum(amountIn)
totalOut = sum(amountOut)
difference = totalOut - totalIn
```

States:

- Balanced: `difference == 0`
- Missing: `totalOut < totalIn`
- Extra: `totalOut > totalIn`

Acceptance criteria:

- User can enter amount out for each player.
- Pot check updates live.
- Balanced/mismatch state updates live.
- Review settlement routes to Confirmation.

### 8.6 Confirmation

Purpose:

Let the user check final numbers before settlement.

Balanced state:

- Header: `CONFIRMATION - BALANCED`
- Player table with in/out values
- Success message
- Confirm and settle button

Mismatch state:

- Header: `CONFIRMATION - MISMATCH`
- Player table with in/out values
- Warning message
- Recount stacks button
- Settlement disabled

Acceptance criteria:

- Balanced sessions can continue to settlement.
- Mismatched sessions cannot settle.
- User can return to Final Stacks to fix values.

### 8.7 Results and Settlement

Purpose:

Show net results and payment instructions.

UI content:

- Header: `RESULTS AND SETTLEMENT`
- Net results list
- Pay up section
- Settlement payment cards
- Send to WhatsApp button
- Save to history button

Net formula:

```text
net = amountOut - amountIn
```

Example:

```text
Alex: 18000 - 10000 = +8000
Ben: 0 - 5000 = -5000
Josh: 10000 - 5000 = +5000
Max: 7000 - 15000 = -8000
```

Acceptance criteria:

- Results are ranked by net amount.
- Winners appear above losers.
- Payments are generated by `SettlementCalculator`.
- Save to history marks the session as settled.

### 8.8 WhatsApp Ready

Purpose:

Generate a shareable settlement message.

UI content:

- Header: `WHATSAPP-READY`
- Ready to send text
- Message preview
- Copy button
- Open WhatsApp button
- Native share button fallback

Share behavior:

- Copy message to clipboard.
- Try WhatsApp URL scheme:

```text
whatsapp://send?text=<encoded-message>
```

- If unavailable, use native iOS share sheet.

Important limitation:

- iOS cannot send the WhatsApp message automatically.
- The user must manually send the prepared message.

Acceptance criteria:

- Message includes session title.
- Message includes net results.
- Message includes payments.
- Copy works.
- Share fallback works.

### 8.9 Session History

Purpose:

Show completed sessions.

UI content:

- Header: `SESSION HISTORY`
- Circle selector
- Time filter
- Session rows

Each row shows:

- Session name
- Date
- Pot size
- Current user result
- Biggest winner
- Biggest loser

Acceptance criteria:

- Completed sessions appear newest first.
- Sessions can be filtered by circle.
- Pot and net results are correct.

### 8.10 Leaderboard

Purpose:

Rank players by all-time results.

UI content:

- Header: `LEADERBOARD`
- Circle and time range
- Top player highlight
- Ranked player list
- Playful footer text

Stats:

```text
totalNet = sum(session net results)
gamesPlayed = count(sessions where player participated)
bestNight = max(session net)
worstNight = min(session net)
currentStreak = consecutive wins or losses
```

Acceptance criteria:

- Players are ranked by total net.
- Games played count is correct.
- Streaks are correct.
- Top player is highlighted.

### 8.11 Head-to-Head

Purpose:

Compare two players across shared sessions.

UI content:

- Header: `HEAD-TO-HEAD`
- Player A
- Player B
- Current leader
- All-time difference
- Sessions won
- Biggest win
- Last game result
- Playful quote

Only count sessions where both players participated.

Acceptance criteria:

- Shared sessions are filtered correctly.
- Head-to-head totals are correct.
- Biggest win and last game are correct.

### 8.12 Player Profile

Purpose:

Show a single player's stats.

UI content:

- Header: `PLAYER PROFILE`
- Avatar
- Name
- Handle
- Circle
- Total won/lost
- Games played
- Best night
- Worst night
- Biggest rival
- Biggest donor
- Badges

Example badges:

- Table Shark: highest total winnings
- House Favourite: top leaderboard player
- Comeback King: biggest comeback or best positive swing
- The Donor: largest total losses
- Silent Assassin: consistent small wins

Acceptance criteria:

- Profile values are calculated from saved sessions.
- Badges are assigned consistently.
- Profile can be opened from leaderboard rows.

## 9. Settlement Calculator

Create `SettlementCalculator`.

Inputs:

- Player results with net amounts

Output:

- List of settlement payments

Algorithm:

1. Reject or return no payments if results do not sum to zero.
2. Create winners list where `net > 0`.
3. Create losers list where `net < 0`.
4. Sort winners by largest positive balance.
5. Sort losers by largest debt.
6. Match one loser to one winner.
7. Payment amount is the smaller of:
   - winner remaining amount
   - loser remaining debt
8. Reduce both remaining balances.
9. Continue until all balances are zero.

Example:

```text
Alex +8000
Josh +5000
Ben -5000
Max -8000
```

Output:

```text
Max pays Alex 8000
Ben pays Josh 5000
```

Acceptance criteria:

- One winner and one loser works.
- Multiple winners and losers work.
- Zero-net players are ignored.
- Payments settle all debts exactly.
- Mismatched totals do not settle.

## 10. Stats Calculator

Create `StatsCalculator`.

Responsibilities:

- Total net by player
- Games played by player
- Best night
- Worst night
- Current win/loss streak
- Biggest winner per session
- Biggest loser per session
- Head-to-head comparisons
- Badge assignment

Acceptance criteria:

- Calculations use settled sessions only.
- Stats update after saving a session.
- Leaderboard, profile, and head-to-head screens use the same shared logic.

## 11. Share Message Builder

Create `ShareMessageBuilder`.

Responsibilities:

- Build WhatsApp/share text from a settled session.
- Include session title.
- Include ranked net results.
- Include payments.
- Include short closer line.

Example format:

```text
Friday Night Poker - Settlement

Net Results
Alex +GBP 80
Josh +GBP 50
Ben -GBP 50
Max -GBP 80

Payments
Ben pays Josh GBP 50
Max pays Alex GBP 80

Pay your debts. Keep your dignity.
```

Acceptance criteria:

- Message is deterministic.
- Message uses correct currency formatting.
- Message omits payments if no payments are needed.

## 12. MVP Scope

Build these first:

1. Circle creation
2. Player creation
3. Session setup
4. Live buy-in tracking
5. Final stack entry
6. Pot balance validation
7. Settlement calculation
8. Save session to history
9. Share/copy settlement message
10. Basic leaderboard

Defer these:

- Voice buy-ins
- Cloud sync
- User accounts
- Real-time multiplayer
- Push notifications
- Widgets
- Apple Watch app
- Advanced badge logic

## 13. Build Order

### Step 1: Xcode project foundation

- Create SwiftUI iOS app.
- Enable SwiftData.
- Enable tests.
- Add folder structure.
- Add app entry point.
- Add sample data.

### Step 2: Design system

- Build shared colors.
- Build typography helpers.
- Build buttons.
- Build money labels.
- Build player avatars.
- Build cards.

### Step 3: Core models

- Add `Circle`.
- Add `Player`.
- Add `PokerSession`.
- Add `BuyIn`.
- Add `FinalStack`.
- Add `SettlementPayment`.
- Add `PlayerResult`.

### Step 4: Navigation

- Add `TabView`.
- Add tabs for Circles, History, Board, and You.
- Add `NavigationStack`.
- Add app routes.

### Step 5: Circles

- Build Circles Home.
- Build Circle Card.
- Build New Circle flow.
- Save circles and players.

### Step 6: Session setup

- Build Session Setup screen.
- Add circle selection.
- Add session title.
- Add player selection.
- Create live session.

### Step 7: Live table

- Build Live Table screen.
- Add buy-in button.
- Add pot total.
- Add player buy-in totals.
- Route to final stacks.

### Step 8: Final stacks

- Build Final Stacks screen.
- Add amount-out fields.
- Add live pot check.
- Persist final stack values.

### Step 9: Confirmation

- Build balanced confirmation.
- Build mismatch confirmation.
- Disable settlement when mismatched.

### Step 10: Settlement

- Build `SettlementCalculator`.
- Add unit tests.
- Build Results and Settlement screen.
- Save settlement payments.

### Step 11: Sharing

- Build `ShareMessageBuilder`.
- Add unit tests.
- Build WhatsApp Ready screen.
- Add copy/share actions.

### Step 12: History and stats

- Build Session History.
- Build `StatsCalculator`.
- Add leaderboard.
- Add player profile.
- Add head-to-head comparison.

### Step 13: Polish

- Add empty states.
- Add haptics.
- Add animations.
- Add accessibility labels.
- Test light mode.
- Test dark mode.
- Test smaller iPhone sizes.
- Run UI tests.

## 14. Testing Plan

### Unit tests

`SettlementCalculatorTests`:

- One winner, one loser
- Multiple winners, multiple losers
- Zero-net player
- Exact zero-sum settlement
- Mismatch rejection
- Minimum payment count

`StatsCalculatorTests`:

- Leaderboard order
- Total net
- Games played
- Win streak
- Loss streak
- Best night
- Worst night
- Head-to-head results

`ShareMessageBuilderTests`:

- Session title appears
- Net results appear
- Payments appear
- Currency formatting is correct
- No-payment case is handled

### UI tests

Main happy path:

1. Open app.
2. Create or select a circle.
3. Start a session.
4. Add buy-ins.
5. End the game.
6. Enter final stacks.
7. Confirm balanced pot.
8. Generate settlement.
9. Save to history.
10. View session in history.

Mismatch path:

1. Enter final stacks that do not equal the pot.
2. Confirm mismatch warning appears.
3. Verify settlement is disabled.
4. Recount stacks.
5. Fix values.
6. Continue to settlement.

## 15. Definition of Done for MVP

The MVP is done when:

- User can create a circle.
- User can add players.
- User can start a poker session.
- User can add buy-ins during a live game.
- User can enter final stacks.
- App detects balanced and mismatched pots.
- App prevents settlement when totals do not match.
- App calculates net results.
- App calculates settlement payments.
- User can save a completed session.
- Completed sessions appear in history.
- User can copy or share the settlement message.
- Basic leaderboard works.
- App runs on the latest available iPhone simulator.
- Core calculator unit tests pass.

