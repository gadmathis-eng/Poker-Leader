import SwiftUI
import SwiftData

struct TableSeatSelectionView: View {
    let buyInAmount: Decimal
    let buyInCurrencyCode: String
    let sessionCurrencyCode: String

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("displayName") private var displayName = "Your name"
    @AppStorage("playerHandle") private var playerHandle = "@yourname"
    @AppStorage("personalTableSeat") private var storedSeatNumber = 0

    @State private var selectedSeat: Int?
    @State private var amountEditor: TableAmountEditor?
    @State private var isGameStarted = false
    @State private var table: OpenTableModel?
    @State private var occupants: [SharedTableSeat] = []
    @State private var hand: SharedTableHand?
    @State private var handMessage: String?
    @State private var showTableSettings = false
    /// Bumped when the stake changes so the felt and editor re-read the table.
    @State private var anteStamp: Decimal = 0

    private static let nextHandPause: Duration = .seconds(2)

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

    /// Sit with the buy-in chosen on the Table tab. If you already have a seat,
    /// keep that stack so a circle table's per-player money is not overwritten.
    private var seatedAmount: Decimal {
        mySeat?.amountDecimal ?? tableBuyInAmount
    }

    private var stackLabel: String {
        MoneyFormatting.plain(seatedAmount, currencyCode: tableCurrencyCode)
    }

    private var anteAmount: Decimal {
        let stored = table?.anteDecimal ?? anteStamp
        if stored > 0 || table?.isStarted == true {
            return stored
        }
        return TableAnte.defaultAmount(forBuyIn: tableBuyInAmount)
    }

    /// Seats can still be changed until the player is dealt into a hand.
    private var canChangeSeat: Bool {
        !isGameStarted || localHandSeat == nil
    }

    private var canEditAnte: Bool {
        table?.isHostLocally ?? true
    }

    private var localHandSeat: SharedTableHandSeat? {
        hand?.seat(forPlayerKey: repo.localPlayerKey)
    }

    /// A finished hand deals the next one itself. The id is the trigger so a
    /// new result starts the pause again, and leaving the screen cancels it.
    private var completedHandID: UUID? {
        guard let hand, hand.isComplete else { return nil }
        return hand.id
    }

    private var mySeat: SharedTableSeat? {
        occupants.first { $0.playerKey == repo.localPlayerKey }
    }

    /// Once cards are out, extra money is added on top of the stack rather than
    /// replacing the buy-in you sat down with.
    private var canAddMoney: Bool {
        table != nil && hand != nil && mySeat != nil
    }

    /// Nothing in front of you and no pot left to win, so the game carries on
    /// without you until you buy in again.
    private var isOutOfMoney: Bool {
        guard canAddMoney, let seat = mySeat else { return false }
        return narration.isOutOfMoney(moneyOnTable: stackAmount(for: seat))
    }

    /// What you have while a hand is out, or what is on the table between hands.
    private var moneyLine: String? {
        guard let seat = mySeat else { return nil }
        if isOutOfMoney {
            return "Nothing left on the table"
        }
        if let stackLine = narration.stackLine {
            return stackLine
        }
        return "\(MoneyFormatting.plain(stackAmount(for: seat), currencyCode: tableCurrencyCode)) on the table"
    }

    private var narration: HandNarration {
        HandNarration(
            hand: hand,
            localPlayerKey: repo.localPlayerKey,
            currencyCode: tableCurrencyCode
        )
    }

    /// Where each seat sits in the dealer's order, so the cards go round the
    /// table in turn rather than landing everywhere at once.
    private var dealPositions: [Int: Int] {
        guard let hand else { return [:] }
        return CardDealSequence.seatPositions(
            inDealerOrder: HandRound.actionOrder(
                seatNumbers: hand.seats.map(\.seatNumber),
                dealerSeat: hand.dealerSeat
            )
        )
    }

    /// Changes with every hand, so a new deal is dealt in rather than swapped.
    private var handDealID: String {
        hand?.id.uuidString ?? ""
    }

    private var layoutOccupants: [TableSeatOccupant] {
        let positions = dealPositions
        let dealID = handDealID
        return occupants.map { seat in
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
                dealID: dealID,
                dealPosition: positions[seat.seatNumber] ?? 0,
                handSummary: isShowingDown ? handSeat?.handSummary : nil,
                isLocalUser: isLocal,
                tapHint: isLocal ? localSeatTapHint : nil,
                isLeader: seat.isHost || seat.playerKey == table?.hostPlayerKey,
                isDealer: hand?.dealerSeat == seat.seatNumber,
                isActing: hand?.actingSeat == seat.seatNumber,
                isFolded: handSeat?.isFolded ?? false,
                isWinner: hand?.winnerSeats.contains(seat.seatNumber) ?? false
            )
        }
    }

    private var localSeatTapHint: String {
        if canAddMoney {
            return isOutOfMoney ? "Buys you in again" : "Puts more money on the table"
        }
        return "Your buy-in. Chosen before you sat down."
    }

    private var centerContent: TableCenterContent {
        guard isGameStarted else {
            return .lobby(
                isPlayEnabled: selectedSeat != nil && seatedAmount > 0,
                inviteCode: table?.inviteCode
            )
        }
        guard let hand else {
            return .waiting(narration.boardTitle)
        }
        return .pot(
            title: narration.boardTitle,
            board: hand.board,
            potLabel: MoneyFormatting.plain(hand.pot, currencyCode: tableCurrencyCode),
            status: narration.boardStatus,
            dealID: handDealID
        )
    }

    private var feltCaption: TableFeltCaption {
        TableFeltCaption(
            hostName: tableHostName,
            stakes: feltStakes,
            seatedCount: occupants.count
        )
    }

    private var tableHostName: String {
        let name = table?.hostDisplayName ?? displayName
        if MemberModel.isPlaceholderName(name) {
            return ""
        }
        return name
    }

    private var feltStakes: String {
        var parts = ["NLH", tableCurrencyCode]
        let shownAnte = hand?.anteDecimal ?? anteAmount
        if shownAnte > 0 {
            parts.append("Ante \(MoneyFormatting.plain(shownAnte, currencyCode: tableCurrencyCode))")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PokerTableSeatLayout(
                    seatCount: SharedTableSeating.seatCount,
                    occupants: layoutOccupants,
                    center: centerContent,
                    caption: feltCaption,
                    onSelect: handleSeatTap,
                    onPlay: startGame
                )
                .frame(height: 500)

                if isGameStarted {
                    handCard
                    if canEditAnte {
                        gameAnteCard
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

                    Button { showTableSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Table settings")
                }
            }
        }
        .onAppear {
            if selectedSeat == nil, storedSeatNumber > 0 {
                selectedSeat = storedSeatNumber
            }
        }
        .task {
            await prepareSharedTable()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                await syncSharedTable()
            }
        }
        .task(id: completedHandID) {
            await dealNextHandWhenReady()
        }
        .sheet(item: $amountEditor) { editor in
            MoneyAmountEditorSheet(editor: editor.state) { text in
                apply(editedAmount: text, for: editor)
            }
            .presentationDetents([.height(420)])
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showTableSettings) {
            if let table {
                NavigationStack {
                    EditTableView(
                        table: table,
                        onChange: handleSettingsChange,
                        showsCloseButton: true
                    )
                }
                .presentationDragIndicator(.visible)
                .presentationBackground(AppTheme.background)
            }
        }
    }

    private var seatHint: some View {
        VStack(spacing: 4) {
            Text("Tap an open seat")
                .font(.headline)
                .foregroundStyle(AppTheme.text)
            if tableBuyInAmount > 0 {
                Text("You'll sit with \(MoneyFormatting.plain(tableBuyInAmount, currencyCode: tableCurrencyCode))")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            } else {
                Text("Table in \(tableCurrencyCode)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
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
                    CardRowView(
                        cards: seat.cards,
                        size: .hand,
                        dealID: handDealID,
                        dealPosition: dealPositions[seat.seatNumber] ?? 0
                    )
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
                    if canAddMoney, !isOutOfMoney {
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
            if isOutOfMoney {
                buyInAgainButton
            }
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
            if isOutOfMoney {
                buyInAgainButton
            }
        }
    }

    private var buyInAgainButton: some View {
        HandActionButton(title: "Buy in again", tint: AppTheme.gold, action: presentTopUpEditor)
    }

    /// Before the first hand: the buy-in you already chose, and the stake.
    private var sitDownCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Buy-in")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.text)
                    Text("Chosen before you sat down. Everyone who joins picks their own.")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                Text(stackLabel)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.gold)
                    .accessibilityLabel("Buy-in \(stackLabel)")
            }

            Divider()
                .overlay(AppTheme.cardBorder)

            AnteEditorRow(
                amount: anteAmount,
                currencyCode: tableCurrencyCode,
                isEditable: canEditAnte,
                action: presentAnteEditor
            )
        }
        .cardSurface()
        .padding(.horizontal)
    }

    /// Hosts can still change the stake after Play. It applies from the next hand.
    private var gameAnteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            AnteEditorRow(
                amount: anteAmount,
                currencyCode: tableCurrencyCode,
                isEditable: canEditAnte,
                action: presentAnteEditor
            )
            if let hand, !hand.isComplete, hand.anteDecimal != anteAmount {
                Text("Applies from the next hand")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .cardSurface()
        .padding(.horizontal)
    }

    private func stackAmount(for seat: SharedTableSeat) -> Decimal {
        if let handSeat = hand?.seat(forPlayerKey: seat.playerKey) {
            return (handSeat.remaining + handSeat.awardedDecimal + handSeat.toppedUpDecimal).roundedToHundredths
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
        rememberAnte(from: table)
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

    /// Lets the table read the winner, then the host deals without anyone
    /// tapping through. Guests wait for that hand to land. If two people do
    /// not have money yet, keep trying as they sit back down.
    private func dealNextHandWhenReady() async {
        guard let table, let hand, hand.isComplete else { return }
        try? await Task.sleep(for: Self.nextHandPause)
        while !Task.isCancelled {
            guard table.hand?.id == hand.id, table.hand?.isComplete == true else { return }
            guard table.isHostLocally else { return }
            do {
                try repo.dealNextHand(on: table)
                handMessage = nil
                withAnimation(.easeOut(duration: 0.18)) {
                    self.hand = table.hand
                    occupants = table.seats
                }
                return
            } catch {
                handMessage = error.localizedDescription
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func handleSeatTap(_ seat: Int) {
        if occupants.contains(where: { $0.seatNumber == seat && $0.playerKey != repo.localPlayerKey }) {
            return
        }

        if selectedSeat == seat {
            if canAddMoney {
                presentTopUpEditor()
            }
            return
        }

        guard canChangeSeat else { return }

        withAnimation(.easeOut(duration: 0.18)) {
            selectedSeat = seat
            storedSeatNumber = seat
        }
        persistSelectedSeat()
    }

    private func presentAnteEditor() {
        guard canEditAnte else { return }
        amountEditor = .ante(
            MoneyAmountEditorState(
                id: UUID(),
                title: "Ante",
                subtitle: isGameStarted ? "Applies from the next hand" : "Per hand",
                currencyCode: tableCurrencyCode,
                text: TableMoney.string(anteAmount),
                maximum: isGameStarted || tableBuyInAmount <= 0 ? nil : tableBuyInAmount
            )
        )
    }

    /// However much you want: buying back in is not held to the buy-in you sat
    /// down with.
    private func presentTopUpEditor() {
        amountEditor = .topUp(
            MoneyAmountEditorState(
                id: UUID(),
                title: isOutOfMoney ? "Buy in again" : "Add money",
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
    }

    private func applyAnteText(_ text: String) {
        guard let table else { return }
        let amount = Decimal(string: MoneyAmountKeypad.normalizedText(text)) ?? 0
        repo.updateAnte(amount, on: table)
        rememberAnte(from: table)
    }

    private func handleSettingsChange() {
        guard let table, (try? repo.table(inviteCode: table.inviteCode)) != nil else {
            showTableSettings = false
            dismiss()
            return
        }
        occupants = table.seats
        isGameStarted = table.isStarted || isGameStarted
        hand = table.hand
        rememberAnte(from: table)
    }

    private func rememberAnte(from table: OpenTableModel) {
        anteStamp = table.anteDecimal
    }

    private func persistSelectedSeat() {
        Task { await persistSelectedSeatNow() }
    }

    private func persistSelectedSeatNow() async {
        guard let table, let selectedSeat, seatedAmount > 0 else { return }
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
        if let resolved {
            rememberAnte(from: resolved)
        }

        if let mine = resolved?.seats.first(where: { $0.playerKey == repo.localPlayerKey }) {
            selectedSeat = mine.seatNumber
            storedSeatNumber = mine.seatNumber
        }

        await publishIfPossible()
        if selectedSeat != nil {
            await persistSelectedSeatNow()
        }
        await syncSharedTable()
    }

    private func syncSharedTable() async {
        guard let table else { return }
        await repo.refresh(table: table)
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
        rememberAnte(from: table)

        if let mine = table.seats.first(where: { $0.playerKey == repo.localPlayerKey }) {
            selectedSeat = mine.seatNumber
            storedSeatNumber = mine.seatNumber
        }
    }

    private func publishIfPossible() async {
        guard let table else { return }
        try? await repo.publishForSharing(table)
    }
}

private enum TableAmountEditor: Identifiable {
    case ante(MoneyAmountEditorState)
    case bet(MoneyAmountEditorState)
    case topUp(MoneyAmountEditorState)

    var state: MoneyAmountEditorState {
        switch self {
        case .ante(let state), .bet(let state), .topUp(let state):
            state
        }
    }

    var id: UUID { state.id }
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
                    CardRowView(cards: seat.cards, size: .board, dealID: seat.id.uuidString)

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
