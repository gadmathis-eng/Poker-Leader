import SwiftUI
import SwiftData

struct TableSeatSelectionView: View {
    let buyInAmount: Decimal
    let buyInCurrencyCode: String
    let sessionCurrencyCode: String

    @Environment(\.modelContext) private var context
    @AppStorage("displayName") private var displayName = "Your name"
    @AppStorage("playerHandle") private var playerHandle = "@yourname"
    @AppStorage("personalTableSeat") private var storedSeatNumber = 0

    @State private var selectedSeat: Int?
    @State private var amountText = ""
    @State private var amountEditor: TableAmountEditor?
    @State private var isGameStarted = false
    @State private var table: OpenTableModel?
    @State private var occupants: [SharedTableSeat] = []
    @State private var hand: SharedTableHand?
    @State private var handMessage: String?

    private static let amountStep = 0.01

    private var repo: TableRepository { TableRepository(context: context) }

    private var playerName: String {
        if !MemberModel.isPlaceholderName(displayName) {
            return displayName
        }
        return MemberModel.normalizedHandle(playerHandle) ?? "You"
    }

    private var tableCurrencyCode: String {
        table?.sessionCurrencyCode ?? sessionCurrencyCode
    }

    private var tableBuyInAmount: Decimal {
        TableCurrencyConversion.amountInTableCurrency(
            buyInAmount,
            from: buyInCurrencyCode,
            to: tableCurrencyCode
        )
    }

    /// The most you can have on the table: what you brought, or more once you
    /// have added to it.
    private var availableMoney: Double {
        let brought = NSDecimalNumber(decimal: tableBuyInAmount).doubleValue
        let seated = NSDecimalNumber(decimal: mySeat?.amountDecimal ?? 0).doubleValue
        return max(brought, seated, 0)
    }

    private var hasMoney: Bool {
        availableMoney > 0
    }

    private var sliderRange: ClosedRange<Double> {
        0...max(availableMoney, Self.amountStep)
    }

    private var seatedAmount: Decimal {
        let committed = MoneyAmountKeypad.committedText(
            amountText,
            maximum: Decimal(string: hundredthsText(availableMoney))
        )
        return Decimal(string: committed) ?? 0
    }

    private var stackLabel: String {
        MoneyFormatting.plain(seatedAmount, currencyCode: tableCurrencyCode)
    }

    private var anteAmount: Decimal {
        let stored = table?.anteDecimal ?? 0
        return stored > 0 ? stored : TableAnte.defaultAmount(forBuyIn: tableBuyInAmount)
    }

    /// Money in stays editable until the player is dealt into a hand.
    private var canEditSeatMoney: Bool {
        !isGameStarted || localHandSeat == nil
    }

    private var localHandSeat: SharedTableHandSeat? {
        hand?.seat(forPlayerKey: repo.localPlayerKey)
    }

    private var mySeat: SharedTableSeat? {
        occupants.first { $0.playerKey == repo.localPlayerKey }
    }

    /// Once cards are out, the slider is no longer the way money reaches the
    /// table: anyone sitting down adds to what they have instead.
    private var canAddMoney: Bool {
        table != nil && hand != nil && mySeat != nil
    }

    /// What you have while a hand is out, or what is on the table between hands.
    private var moneyLine: String? {
        if let stackLine = narration.stackLine {
            return stackLine
        }
        guard let seat = mySeat else { return nil }
        return "\(MoneyFormatting.plain(stackAmount(for: seat), currencyCode: tableCurrencyCode)) on the table"
    }

    private var narration: HandNarration {
        HandNarration(
            hand: hand,
            localPlayerKey: repo.localPlayerKey,
            currencyCode: tableCurrencyCode
        )
    }

    private var layoutOccupants: [TableSeatOccupant] {
        occupants.map { seat in
            let isLocal = seat.playerKey == repo.localPlayerKey
            let handSeat = hand?.seat(forPlayerKey: seat.playerKey)
            let isShowingDown = hand?.showsCards(forSeat: seat.seatNumber) ?? false
            let dealtCards = handSeat?.cards.count ?? 0
            return TableSeatOccupant(
                seatNumber: seat.seatNumber,
                playerName: isLocal ? playerName : seat.playerName,
                stackLabel: MoneyFormatting.plain(stackAmount(for: seat), currencyCode: tableCurrencyCode),
                committedLabel: (handSeat?.committedDecimal ?? 0) > 0
                    ? MoneyFormatting.plain(handSeat?.committedDecimal ?? 0, currencyCode: tableCurrencyCode)
                    : nil,
                cards: isLocal || isShowingDown ? (handSeat?.cards ?? []) : [],
                faceDownCount: isLocal || isShowingDown ? 0 : dealtCards,
                handSummary: isShowingDown ? handSeat?.handSummary : nil,
                isLocalUser: isLocal,
                isLeader: seat.isHost || seat.playerKey == table?.hostPlayerKey,
                isDealer: hand?.dealerSeat == seat.seatNumber,
                isActing: hand?.actingSeat == seat.seatNumber,
                isFolded: handSeat?.isFolded ?? false,
                isWinner: hand?.winnerSeats.contains(seat.seatNumber) ?? false
            )
        }
    }

    private var centerContent: TableCenterContent {
        guard isGameStarted else {
            return .play(isEnabled: selectedSeat != nil && seatedAmount > 0)
        }
        guard let hand else {
            return .waiting(narration.boardTitle)
        }
        return .pot(
            title: narration.boardTitle,
            board: hand.board,
            potLabel: MoneyFormatting.plain(hand.pot, currencyCode: tableCurrencyCode),
            status: narration.boardStatus
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                PokerTableSeatLayout(
                    seatCount: SharedTableSeating.seatCount,
                    occupants: layoutOccupants,
                    center: centerContent,
                    onSelect: handleSeatTap,
                    onPlay: startGame
                )
                .frame(height: 430)
                .padding(.horizontal)

                if isGameStarted {
                    handCard
                    if hand == nil, selectedSeat != nil {
                        moneyInCard
                    }
                } else if selectedSeat == nil {
                    seatHint
                } else {
                    sitDownCard
                }
            }
            .padding(.vertical)
        }
        .background(AppTheme.background)
        .navigationTitle("Table")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let table {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    InviteCodeCopyLabel(code: table.inviteCode, style: .compact)

                    ShareLink(
                        item: TableInviteSharing.url(forInviteCode: table.inviteCode),
                        subject: Text("Join my Pot Master table"),
                        message: Text(TableInviteSharing.message(forInviteCode: table.inviteCode, hostName: table.hostDisplayName))
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share table")
                }
            }
        }
        .onAppear {
            if selectedSeat == nil, storedSeatNumber > 0 {
                selectedSeat = storedSeatNumber
            }
            if amountText.isEmpty {
                resetAmountToFullStack()
            }
        }
        .task {
            await prepareSharedTable()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                await syncSharedTable()
            }
        }
        .sheet(item: $amountEditor) { editor in
            MoneyAmountEditorSheet(editor: editor.state) { text in
                apply(editedAmount: text, for: editor)
            }
            .presentationDetents([.height(420)])
            .presentationDragIndicator(.visible)
        }
    }

    private var seatHint: some View {
        VStack(spacing: 4) {
            Text("Tap an open seat")
                .font(.headline)
                .foregroundStyle(AppTheme.text)
            Text("Table in \(tableCurrencyCode)")
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }

    /// Everything a hand asks of you in one place: your cards, what you have,
    /// and the buttons.
    private var handCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                if let seat = localHandSeat, seat.isDealtCards {
                    CardRowView(cards: seat.cards, size: .hand)
                        .opacity(seat.isFolded ? 0.4 : 1)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(narration.title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.text)
                    Text(narration.detail)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            handActions

            if let hand, hand.isRevealed {
                ShowdownRows(
                    contenders: hand.contenders,
                    winnerSeats: hand.winnerSeats,
                    localPlayerKey: repo.localPlayerKey
                )
            }

            if moneyLine != nil || canAddMoney {
                HStack(alignment: .firstTextBaseline) {
                    if let moneyLine {
                        Text(moneyLine)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.muted)
                    }
                    Spacer(minLength: 8)
                    if canAddMoney {
                        Button("Add money", action: presentTopUpEditor)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.gold)
                            .buttonStyle(.plain)
                    }
                }
            }

            if let handMessage {
                Text(handMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.negative)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .padding(.horizontal)
    }

    @ViewBuilder
    private var handActions: some View {
        switch narration.turn {
        case .handOver:
            HandActionButton(title: "Next hand", tint: AppTheme.positive, action: dealNextHand)
        case .toAct(let toCall):
            HStack(spacing: 10) {
                if toCall > 0 {
                    HandActionButton(
                        title: "Call \(MoneyFormatting.plain(toCall, currencyCode: tableCurrencyCode))",
                        tint: AppTheme.positive,
                        action: { submit(.call) }
                    )
                } else {
                    HandActionButton(
                        title: "Check",
                        tint: AppTheme.card,
                        action: { submit(.check) }
                    )
                }
                HandActionButton(
                    title: toCall > 0 ? "Raise" : "Bet",
                    tint: AppTheme.gold,
                    action: presentBetEditor
                )
                HandActionButton(
                    title: "Fold",
                    tint: AppTheme.negative,
                    action: { submit(.fold) }
                )
            }
        case .waitingForPlayers, .notDealtIn, .folded, .waitingForOthers:
            EmptyView()
        }
    }

    /// Before the first hand: what you are sitting down with, and the stake.
    private var sitDownCard: some View {
        VStack(spacing: 14) {
            moneyInRows

            Divider()
                .overlay(AppTheme.cardBorder)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ante")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.text)
                    Text("What everyone puts in to stay in the hand")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                Button(action: presentAnteEditor) {
                    Text(MoneyFormatting.plain(anteAmount, currencyCode: tableCurrencyCode))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.gold)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit ante")
            }
        }
        .cardSurface()
        .padding(.horizontal)
    }

    private var moneyInCard: some View {
        moneyInRows
            .cardSurface()
            .padding(.horizontal)
    }

    private var moneyInRows: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Money in")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.text)
                Spacer()
                Button(action: presentAmountEditor) {
                    Text(stackLabel)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.gold)
                }
                .buttonStyle(.plain)
                .disabled(!hasMoney)
                .accessibilityLabel("Edit money in")
            }

            Slider(value: hundredthsSliderBinding, in: sliderRange, step: Self.amountStep)
                .tint(AppTheme.positive)
                .disabled(!hasMoney)

            HStack {
                Text(MoneyFormatting.plain(0, currencyCode: tableCurrencyCode))
                Spacer()
                Text(MoneyFormatting.plain(tableBuyInAmount, currencyCode: tableCurrencyCode))
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(AppTheme.muted)
        }
    }

    private var hundredthsSliderBinding: Binding<Double> {
        Binding(
            get: {
                clampedHundredths(Double(MoneyAmountKeypad.normalizedText(amountText)) ?? 0)
            },
            set: { newValue in
                amountText = hundredthsText(newValue)
            }
        )
    }

    private func stackAmount(for seat: SharedTableSeat) -> Decimal {
        if let handSeat = hand?.seat(forPlayerKey: seat.playerKey) {
            return (handSeat.remaining + handSeat.awardedDecimal + handSeat.toppedUpDecimal).roundedToHundredths
        }
        if seat.playerKey == repo.localPlayerKey, !isGameStarted {
            return seatedAmount
        }
        return seat.amountDecimal
    }

    private func startGame() {
        guard selectedSeat != nil, seatedAmount > 0, !isGameStarted else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            isGameStarted = true
        }
        guard let table else { return }
        persistSelectedSeat()
        repo.updateAnte(anteAmount, on: table)
        dealHandIfPossible(on: table)
    }

    private func dealHandIfPossible(on table: OpenTableModel) {
        if needsDeal(on: table), (try? repo.dealHand(on: table)) == nil {
            repo.markStarted(table)
        }
        withAnimation(.easeOut(duration: 0.18)) {
            hand = table.hand
        }
    }

    /// A table with no hand, or one dealt by a build that did not deal cards,
    /// needs a fresh deck before it can be played out.
    private func needsDeal(on table: OpenTableModel) -> Bool {
        guard let hand = table.hand else { return true }
        return hand.needsRedeal
    }

    private func submit(_ move: HandMove, amount: Decimal? = nil) {
        guard let table, let hand else { return }
        do {
            let next = try HandRound.apply(
                move: move,
                amount: amount,
                playerKey: repo.localPlayerKey,
                to: hand
            )
            handMessage = nil
            withAnimation(.easeOut(duration: 0.18)) {
                self.hand = next
            }
            repo.updateHand(next, on: table)
            occupants = table.seats
        } catch {
            handMessage = error.localizedDescription
        }
    }

    private func dealNextHand() {
        guard let table else { return }
        do {
            try repo.dealNextHand(on: table)
            handMessage = nil
            withAnimation(.easeOut(duration: 0.18)) {
                hand = table.hand
                occupants = table.seats
            }
        } catch {
            handMessage = error.localizedDescription
        }
    }

    private func handleSeatTap(_ seat: Int) {
        guard canEditSeatMoney else { return }

        if occupants.contains(where: { $0.seatNumber == seat && $0.playerKey != repo.localPlayerKey }) {
            return
        }

        if selectedSeat == seat {
            presentAmountEditor()
            return
        }

        withAnimation(.easeOut(duration: 0.18)) {
            selectedSeat = seat
            storedSeatNumber = seat
            resetAmountToFullStack()
        }
        persistSelectedSeat()
    }

    private func presentAmountEditor() {
        guard hasMoney else { return }
        amountEditor = .seat(
            MoneyAmountEditorState(
                id: UUID(),
                title: "Money in",
                currencyCode: tableCurrencyCode,
                text: amountText.isEmpty ? "0" : amountText,
                maximum: Decimal(string: hundredthsText(availableMoney))
            )
        )
    }

    private func presentAnteEditor() {
        amountEditor = .ante(
            MoneyAmountEditorState(
                id: UUID(),
                title: "Ante",
                subtitle: "Per hand",
                currencyCode: tableCurrencyCode,
                text: TableMoney.string(anteAmount),
                maximum: tableBuyInAmount
            )
        )
    }

    private func presentTopUpEditor() {
        amountEditor = .topUp(
            MoneyAmountEditorState(
                id: UUID(),
                title: "Add money",
                subtitle: localHandSeat == nil ? "Goes on the table now" : "Plays from the next hand",
                currencyCode: tableCurrencyCode,
                text: "0",
                minimum: TableMoney.penny
            )
        )
    }

    /// The keypad opens empty so the whole bet is typed in, rather than starting
    /// on a size nobody asked for.
    private func presentBetEditor() {
        guard let hand, let seat = localHandSeat else { return }
        let smallest = HandRound.minimumBet(in: hand, forPlayerKey: seat.playerKey)
        amountEditor = .bet(
            MoneyAmountEditorState(
                id: UUID(),
                title: hand.amountToCall(forPlayerKey: seat.playerKey) > 0 ? "Raise to" : "\(hand.street.title) bet",
                subtitle: "Total on this street · at least \(MoneyFormatting.plain(smallest, currencyCode: tableCurrencyCode))",
                currencyCode: tableCurrencyCode,
                text: "0",
                minimum: smallest,
                maximum: seat.streetCap
            )
        )
    }

    private func apply(editedAmount text: String, for editor: TableAmountEditor) {
        switch editor {
        case .seat:
            applyAmountText(text)
        case .ante:
            applyAnteText(text)
        case .bet:
            submit(.bet, amount: Decimal(string: MoneyAmountKeypad.normalizedText(text)) ?? 0)
        case .topUp:
            addMoney(Decimal(string: MoneyAmountKeypad.normalizedText(text)) ?? 0)
        }
    }

    private func addMoney(_ amount: Decimal) {
        guard let table, repo.addMoney(amount, on: table) else { return }
        handMessage = nil
        withAnimation(.easeOut(duration: 0.18)) {
            hand = table.hand
            occupants = table.seats
        }
        if localHandSeat == nil {
            amountText = hundredthsText(
                NSDecimalNumber(decimal: mySeat?.amountDecimal ?? 0).doubleValue
            )
        }
    }

    private func resetAmountToFullStack() {
        amountText = hundredthsText(availableMoney)
    }

    private func applyAmountText(_ text: String) {
        let committed = MoneyAmountKeypad.committedText(
            text,
            maximum: Decimal(string: hundredthsText(availableMoney))
        )
        amountText = hundredthsText(Double(committed) ?? 0)
        persistSelectedSeat()
    }

    private func applyAnteText(_ text: String) {
        guard let table else { return }
        let amount = Decimal(string: MoneyAmountKeypad.normalizedText(text)) ?? 0
        repo.updateAnte(amount, on: table)
    }

    private func clampedHundredths(_ value: Double) -> Double {
        let clamped = min(max(value, 0), availableMoney)
        return (clamped * 100).rounded() / 100
    }

    private func hundredthsText(_ value: Double) -> String {
        String(format: "%.2f", clampedHundredths(value))
    }

    private func persistSelectedSeat() {
        Task { await persistSelectedSeatNow() }
    }

    private func persistSelectedSeatNow() async {
        guard let table, let selectedSeat else { return }
        do {
            try await repo.occupySeat(
                on: table,
                seatNumber: selectedSeat,
                playerName: playerName,
                handle: MemberModel.normalizedHandle(playerHandle),
                amount: seatedAmount
            )
            occupants = table.seats
        } catch {
            await syncSharedTable()
        }
    }

    private func prepareSharedTable() async {
        let hostName = playerName
        let resolved = (try? repo.activeTable()) ?? (try? repo.ensureHostTable(
            sessionCurrencyCode: sessionCurrencyCode,
            hostDisplayName: hostName
        ))
        table = resolved
        occupants = resolved?.seats ?? []
        isGameStarted = resolved?.isStarted ?? false
        hand = resolved?.hand

        if let resolved, resolved.isHostLocally, !resolved.isStarted, resolved.anteDecimal == 0 {
            repo.updateAnte(TableAnte.defaultAmount(forBuyIn: tableBuyInAmount), on: resolved)
        }

        if let mine = resolved?.seats.first(where: { $0.playerKey == repo.localPlayerKey }) {
            selectedSeat = mine.seatNumber
            storedSeatNumber = mine.seatNumber
            amountText = hundredthsText(NSDecimalNumber(decimal: mine.amountDecimal).doubleValue)
        }

        await publishIfPossible()
        if selectedSeat != nil {
            await persistSelectedSeatNow()
        }
        await syncSharedTable()
    }

    private func syncSharedTable() async {
        guard let table else { return }
        if selectedSeat != nil, ownsMoneyIn(on: table) {
            repo.updateLocalAmount(on: table, amount: seatedAmount)
        }
        await repo.refresh(table: table)
        if ownsMoneyIn(on: table) {
            mergeLocalSeat(into: table)
        }
        occupants = table.seats
        isGameStarted = table.isStarted || isGameStarted

        if let finished = table.hand, finished.isComplete {
            repo.payOutHand(finished, on: table)
            occupants = table.seats
        }

        if isGameStarted, needsDeal(on: table), table.isHostLocally {
            try? repo.dealHand(on: table)
            occupants = table.seats
        }

        withAnimation(.easeOut(duration: 0.18)) {
            hand = table.hand
        }

        if let mine = table.seats.first(where: { $0.playerKey == repo.localPlayerKey }) {
            selectedSeat = mine.seatNumber
            storedSeatNumber = mine.seatNumber
        }
    }

    /// Money in follows the slider until the table has been dealt a hand. After
    /// that a player's money is whatever the poker left them with, so a busted
    /// stack is not quietly topped back up.
    private func ownsMoneyIn(on table: OpenTableModel) -> Bool {
        table.hand == nil && !repo.isDealtIn(table)
    }

    private func mergeLocalSeat(into table: OpenTableModel) {
        guard let selectedSeat else { return }
        do {
            table.seats = try SharedTableSeating.occupy(
                seats: table.seats,
                seatNumber: selectedSeat,
                playerKey: repo.localPlayerKey,
                playerName: playerName,
                handle: MemberModel.normalizedHandle(playerHandle),
                amount: seatedAmount,
                isHost: table.hostPlayerKey == repo.localPlayerKey
            )
            try? context.save()
        } catch {
            return
        }
    }

    private func publishIfPossible() async {
        guard let table else { return }
        try? await repo.publishForSharing(table)
    }
}

private enum TableAmountEditor: Identifiable {
    case seat(MoneyAmountEditorState)
    case ante(MoneyAmountEditorState)
    case bet(MoneyAmountEditorState)
    case topUp(MoneyAmountEditorState)

    var state: MoneyAmountEditorState {
        switch self {
        case .seat(let state), .ante(let state), .bet(let state), .topUp(let state):
            state
        }
    }

    var id: UUID { state.id }
}

private enum TableCenterContent: Equatable {
    case play(isEnabled: Bool)
    case waiting(String)
    case pot(title: String, board: [PlayingCard], potLabel: String, status: String)
}

private struct TableSeatOccupant: Equatable {
    var seatNumber: Int
    var playerName: String
    var stackLabel: String
    var committedLabel: String?
    var cards: [PlayingCard] = []
    var faceDownCount: Int = 0
    var handSummary: String?
    var isLocalUser: Bool
    var isLeader: Bool
    var isDealer: Bool
    var isActing: Bool
    var isFolded: Bool
    var isWinner: Bool
}

private struct PokerTableSeatLayout: View {
    let seatCount: Int
    let occupants: [TableSeatOccupant]
    let center: TableCenterContent
    let onSelect: (Int) -> Void
    let onPlay: () -> Void

    private let seatWidth: CGFloat = 92
    private let seatHeight: CGFloat = 84

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let radiusX = (size.width - seatWidth) / 2
            let radiusY = (size.height - seatHeight) / 2

            ZStack {
                TableFelt()
                    .frame(
                        width: max(size.width - seatWidth * 1.25, 80),
                        height: max(size.height - seatHeight * 1.55, 80)
                    )

                TableCenterView(content: center, onPlay: onPlay)

                ForEach(1...seatCount, id: \.self) { seat in
                    let occupant = occupants.first { $0.seatNumber == seat }
                    let angle = seatAngle(for: seat)
                    SeatChip(
                        seatNumber: seat,
                        occupant: occupant,
                        action: { onSelect(seat) }
                    )
                    .frame(width: seatWidth, height: seatHeight)
                    .offset(
                        x: cos(angle) * radiusX,
                        y: sin(angle) * radiusY
                    )
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }

    private func seatAngle(for seat: Int) -> CGFloat {
        let step = 2 * CGFloat.pi / CGFloat(seatCount)
        return CGFloat.pi / 2 + step * CGFloat(seat - 1)
    }
}

private struct TableCenterView: View {
    let content: TableCenterContent
    let onPlay: () -> Void

    var body: some View {
        switch content {
        case .play(let isEnabled):
            TablePlayButton(isEnabled: isEnabled, action: onPlay)
        case .waiting(let text):
            Text(text)
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.muted)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Capsule().fill(AppTheme.card))
        case .pot(let title, let board, let potLabel, let status):
            VStack(spacing: 6) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.muted)
                BoardCardsView(cards: board)
                Text(potLabel)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(AppTheme.gold)
                    .monospacedDigit()
                Text(status)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .fill(AppTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(AppTheme.gold.opacity(0.5), lineWidth: 2)
            )
            .accessibilityElement(children: .combine)
        }
    }
}

private struct TablePlayButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Play")
                .font(.headline.weight(.bold))
                .foregroundStyle(isEnabled ? AppTheme.contrastText : AppTheme.muted)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(isEnabled ? AppTheme.positive : AppTheme.card)
                )
                .overlay(
                    Capsule()
                        .stroke(
                            isEnabled ? AppTheme.positive : AppTheme.cardBorder,
                            lineWidth: 2
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("Play")
        .accessibilityHint(isEnabled ? "Deals the first hand" : "Sit down to start")
    }
}

private struct TableFelt: View {
    var body: some View {
        Ellipse()
            .fill(AppTheme.positive.opacity(0.18))
            .overlay(
                Ellipse()
                    .stroke(AppTheme.positive.opacity(0.45), lineWidth: 3)
            )
    }
}

private struct HandActionButton: View {
    let title: String
    let tint: Color
    let action: () -> Void

    private var usesContrastText: Bool {
        tint != AppTheme.card
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(tint)
                .foregroundStyle(usesContrastText ? AppTheme.contrastText : AppTheme.text)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(usesContrastText ? .clear : AppTheme.cardBorder)
                )
        }
        .buttonStyle(.plain)
    }
}

/// Everyone still in the hand with their cards face up, once the betting is done.
private struct ShowdownRows: View {
    let contenders: [SharedTableHandSeat]
    let winnerSeats: [Int]
    let localPlayerKey: String

    var body: some View {
        VStack(spacing: 8) {
            ForEach(contenders) { seat in
                let isWinner = winnerSeats.contains(seat.seatNumber)
                HStack(spacing: 10) {
                    CardRowView(cards: seat.cards, size: .board)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(seat.playerKey == localPlayerKey ? "You" : seat.playerName)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppTheme.text)
                            .lineLimit(1)
                        if let summary = seat.handSummary {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(isWinner ? AppTheme.gold : AppTheme.muted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    Spacer(minLength: 0)

                    if isWinner {
                        Image(systemName: "trophy.fill")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(AppTheme.gold)
                    }
                }
                .padding(10)
                .background(AppTheme.background)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isWinner ? AppTheme.gold : AppTheme.cardBorder, lineWidth: isWinner ? 2 : 1)
                )
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct SeatChip: View {
    let seatNumber: Int
    let occupant: TableSeatOccupant?
    let action: () -> Void

    private var isOccupied: Bool { occupant != nil }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                if let occupant {
                    HStack(spacing: 3) {
                        if occupant.isLeader {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(AppTheme.gold)
                        }
                        Text(occupant.playerName)
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    Text(occupant.stackLabel)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(AppTheme.contrastText.opacity(0.8))
                    if !occupant.cards.isEmpty || occupant.faceDownCount > 0 {
                        CardRowView(
                            cards: occupant.cards,
                            faceDownCount: occupant.faceDownCount,
                            size: .seat
                        )
                        .padding(.vertical, 1)
                    }
                    if occupant.isFolded {
                        Text("Folded")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(AppTheme.contrastText.opacity(0.7))
                    } else if let committedLabel = occupant.committedLabel {
                        Text("in \(committedLabel)")
                            .font(.system(size: 9, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(AppTheme.contrastText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(AppTheme.gold))
                    }
                } else {
                    Image(systemName: "chair.lounge.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Seat \(seatNumber)")
                        .font(.caption2.weight(.semibold))
                }
            }
            .foregroundStyle(isOccupied ? AppTheme.contrastText : AppTheme.text)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(strokeColor, lineWidth: strokeWidth)
            )
            .opacity(occupant?.isFolded == true ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(occupant?.isLocalUser == false)
        .accessibilityHint(accessibilityHint)
        .accessibilityLabel(occupancyAccessibilityLabel)
    }

    private var fillColor: Color {
        guard isOccupied else { return AppTheme.card }
        return occupant?.isFolded == true ? AppTheme.muted : AppTheme.positive
    }

    private var strokeColor: Color {
        if occupant?.isActing == true || occupant?.isWinner == true {
            return AppTheme.gold
        }
        return isOccupied ? AppTheme.positive : AppTheme.cardBorder
    }

    private var strokeWidth: CGFloat {
        if occupant?.isActing == true || occupant?.isWinner == true {
            return 3
        }
        return isOccupied ? 2 : 1
    }

    private var occupancyAccessibilityLabel: String {
        guard let occupant else { return "Seat \(seatNumber)" }
        var label = occupant.isLeader ? "\(occupant.playerName), party leader" : occupant.playerName
        if occupant.isDealer {
            label += ", dealer"
        }
        if occupant.isFolded {
            label += ", folded"
        } else if occupant.isActing {
            label += ", to act"
        }
        if let summary = occupant.handSummary {
            label += ", \(summary)"
        }
        return label
    }

    private var accessibilityHint: String {
        if occupant?.isLocalUser == false {
            return "Seat taken"
        }
        if isOccupied {
            return "Your buy-in. Tap to edit the amount."
        }
        return "Sits at this seat"
    }
}
