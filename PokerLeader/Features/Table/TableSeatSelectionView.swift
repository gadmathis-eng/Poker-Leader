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

    private var availableMoney: Double {
        max(NSDecimalNumber(decimal: tableBuyInAmount).doubleValue, 0)
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

    private var displayedAnte: Decimal {
        hand?.anteDecimal ?? anteAmount
    }

    /// Money in stays editable until the player is dealt into a hand.
    private var canEditSeatMoney: Bool {
        !isGameStarted || localHandSeat == nil
    }

    private var localHandSeat: SharedTableHandSeat? {
        hand?.seat(forPlayerKey: repo.localPlayerKey)
    }

    private var isLocalTurn: Bool {
        hand?.isActing(playerKey: repo.localPlayerKey) ?? false
    }

    private var amountToCall: Decimal {
        hand?.amountToCall(forPlayerKey: repo.localPlayerKey) ?? 0
    }

    private var board: [PlayingCard] {
        hand?.board ?? []
    }

    /// What your two cards and the cards on the table add up to right now.
    private var localHandSummary: String? {
        guard let seat = localHandSeat, seat.isDealtCards, !seat.isFolded else { return nil }
        if let rank = PokerHandEvaluator.best(from: seat.cards + board) {
            return rank.summary
        }
        return PokerHandEvaluator.startingHandName(seat.cards)
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
            return .waiting("Waiting for players")
        }
        return .pot(
            title: hand.isComplete ? "Hand \(hand.handNumber)" : "Hand \(hand.handNumber) · \(hand.street.title)",
            board: hand.board,
            potLabel: MoneyFormatting.plain(hand.pot, currencyCode: tableCurrencyCode),
            status: potStatus(for: hand)
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    if selectedSeat == nil && !isGameStarted {
                        Text("Tap an open seat")
                            .font(.title3.bold())
                            .foregroundStyle(AppTheme.text)
                    }
                    Text("Table in \(tableCurrencyCode)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                .padding(.horizontal)

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
                    if let seat = localHandSeat, seat.isDealtCards {
                        yourCardsSection(seat)
                    }
                    handSection
                    if selectedSeat != nil, localHandSeat == nil {
                        amountControls
                    }
                } else if selectedSeat != nil {
                    anteControls
                    amountControls
                }
            }
            .padding(.vertical)
        }
        .background(AppTheme.background)
        .navigationTitle("Table")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let table {
                ToolbarItem(placement: .topBarTrailing) {
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

    private var anteControls: some View {
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
        .padding(14)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.cardBorder)
        )
        .padding(.horizontal)
    }

    private var amountControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Money in")
                Spacer()
                Button(action: presentAmountEditor) {
                    Text(stackLabel)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.gold)
                }
                .buttonStyle(.plain)
                .disabled(!hasMoney)
            }

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Slider(value: hundredthsSliderBinding, in: sliderRange, step: Self.amountStep)
                        .tint(AppTheme.positive)
                        .disabled(!hasMoney)

                    Button(action: presentAmountEditor) {
                        Text(amountText.isEmpty ? "0.00" : amountText)
                            .multilineTextAlignment(.center)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(hasMoney ? AppTheme.text : AppTheme.muted)
                            .frame(width: 72)
                            .padding(.vertical, 8)
                            .background(AppTheme.background)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9)
                                    .stroke(AppTheme.cardBorder)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasMoney)
                    .accessibilityLabel("Edit money in")
                }

                HStack {
                    Text(MoneyFormatting.plain(0, currencyCode: tableCurrencyCode))
                    Spacer()
                    Text(MoneyFormatting.plain(tableBuyInAmount, currencyCode: tableCurrencyCode))
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.muted)
            }
            .padding(14)
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(AppTheme.cardBorder)
            )
        }
        .padding(.horizontal)
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

    private func yourCardsSection(_ seat: SharedTableHandSeat) -> some View {
        HStack(spacing: 14) {
            CardRowView(cards: seat.cards, size: .hand)
                .opacity(seat.isFolded ? 0.4 : 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(seat.isFolded ? "You folded" : "Your hand")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.text)
                Text(localHandSummary ?? "Waiting for the flop")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(seat.isFolded ? AppTheme.muted : AppTheme.gold)
                Text("\(MoneyFormatting.plain(seat.remaining, currencyCode: tableCurrencyCode)) behind")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.cardBorder)
        )
        .padding(.horizontal)
    }

    private var handSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: hand.map { "Hand \($0.handNumber) · \($0.street.title)" } ?? "Pre-flop")
                Spacer()
                Text("Ante \(MoneyFormatting.plain(displayedAnte, currencyCode: tableCurrencyCode))")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.muted)
            }

            VStack(spacing: 12) {
                if let hand {
                    handActions(for: hand)
                } else {
                    Text("Share the table so a friend can sit down. The first hand deals as soon as two of you have money on the table.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let handMessage {
                    Text(handMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.negative)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(AppTheme.cardBorder)
            )
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func handActions(for hand: SharedTableHand) -> some View {
        if hand.isComplete {
            HandPrompt(title: resultTitle(for: hand), detail: resultDetail(for: hand))
            if hand.isRevealed {
                ShowdownRows(
                    contenders: hand.contenders,
                    winnerSeats: hand.winnerSeats,
                    localPlayerKey: repo.localPlayerKey
                )
            }
            HandActionButton(title: "Next hand", tint: AppTheme.positive, action: dealNextHand)
        } else if isLocalTurn, let seat = localHandSeat {
            HandPrompt(
                title: turnTitle(for: hand),
                detail: turnDetail(for: hand, seat: seat)
            )
            HStack(spacing: 10) {
                if amountToCall > 0 {
                    HandActionButton(
                        title: "Call \(MoneyFormatting.plain(amountToCall, currencyCode: tableCurrencyCode))",
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
                    title: amountToCall > 0 ? "Raise" : "Bet",
                    tint: AppTheme.gold,
                    action: presentBetEditor
                )
                HandActionButton(
                    title: "Fold",
                    tint: AppTheme.negative,
                    action: { submit(.fold) }
                )
            }
        } else if localHandSeat == nil {
            HandPrompt(
                title: "You are in from the next hand",
                detail: "This hand started before you sat down."
            )
        } else if localHandSeat?.isFolded == true {
            HandPrompt(
                title: "You folded",
                detail: waitingDetail(for: hand)
            )
        } else {
            HandPrompt(
                title: waitingDetail(for: hand),
                detail: "You are in for \(MoneyFormatting.plain(localHandSeat?.committedDecimal ?? 0, currencyCode: tableCurrencyCode))."
            )
        }
    }

    private func turnTitle(for hand: SharedTableHand) -> String {
        switch hand.street {
        case .preflop:
            amountToCall > 0 ? "Are you in?" : "Your turn before the flop"
        case .flop, .turn, .river:
            "Your turn on the \(hand.street.title.lowercased())"
        case .showdown:
            "Cards up"
        }
    }

    private func turnDetail(for hand: SharedTableHand, seat: SharedTableHandSeat) -> String {
        var parts: [String] = []
        if let localHandSummary {
            parts.append(localHandSummary)
        }
        if amountToCall > 0 {
            let owed = MoneyFormatting.plain(amountToCall, currencyCode: tableCurrencyCode)
            parts.append(hand.callTarget == hand.anteDecimal ? "Ante \(owed) to stay in" : "\(owed) to call")
        } else {
            parts.append("Nothing to put in yet")
        }
        parts.append("\(MoneyFormatting.plain(seat.remaining, currencyCode: tableCurrencyCode)) behind")
        return parts.joined(separator: " · ")
    }

    private func waitingDetail(for hand: SharedTableHand) -> String {
        guard let name = hand.actingSeatName else { return "Waiting for the table" }
        return "Waiting for \(name)"
    }

    private func resultTitle(for hand: SharedTableHand) -> String {
        let winners = hand.winners
        guard let first = winners.first else { return "Hand over" }

        if winners.count > 1 {
            let names = winners.map { $0.playerKey == repo.localPlayerKey ? "You" : $0.playerName }
            let joined = names.count == 2
                ? names.joined(separator: " and ")
                : names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
            return "\(joined) split \(MoneyFormatting.plain(hand.pot, currencyCode: tableCurrencyCode))"
        }

        let taken = MoneyFormatting.plain(first.awardedDecimal, currencyCode: tableCurrencyCode)
        let who = first.playerKey == repo.localPlayerKey ? "You take" : "\(first.playerName) takes"
        return "\(who) \(taken)"
    }

    private func resultDetail(for hand: SharedTableHand) -> String {
        if let summary = hand.resultSummary {
            return summary
        }
        return "Pot pushed to the winner."
    }

    private func potStatus(for hand: SharedTableHand) -> String {
        if hand.isComplete {
            let winners = hand.winners
            if winners.count > 1 {
                return "Split pot"
            }
            if let winner = winners.first {
                return "\(winner.playerName) wins"
            }
            return "Hand over"
        }
        if isLocalTurn {
            return "Your turn"
        }
        return waitingDetail(for: hand)
    }

    private func stackAmount(for seat: SharedTableSeat) -> Decimal {
        if let handSeat = hand?.seat(forPlayerKey: seat.playerKey) {
            return (handSeat.remaining + handSeat.awardedDecimal).roundedToHundredths
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

    private func presentBetEditor() {
        guard let hand, let seat = localHandSeat else { return }
        amountEditor = .bet(
            MoneyAmountEditorState(
                id: UUID(),
                title: amountToCall > 0 ? "Raise to" : "\(hand.street.title) bet",
                subtitle: "Total in front of you on this street",
                currencyCode: tableCurrencyCode,
                text: TableMoney.string(HandRound.suggestedBet(in: hand, forPlayerKey: seat.playerKey)),
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

    var state: MoneyAmountEditorState {
        switch self {
        case .seat(let state), .ante(let state), .bet(let state):
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

private struct HandPrompt: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.text)
            Text(detail)
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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
