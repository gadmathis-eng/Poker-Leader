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
    @State private var editingAmount: MoneyAmountEditorState?
    @State private var isGameStarted = false
    @State private var table: OpenTableModel?
    @State private var occupants: [SharedTableSeat] = []
    @State private var shareError: String?
    @State private var showSignIn = false

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

    private var layoutOccupants: [TableSeatOccupant] {
        occupants.map { seat in
            let isLocal = seat.playerKey == repo.localPlayerKey
            return TableSeatOccupant(
                seatNumber: seat.seatNumber,
                playerName: isLocal ? playerName : seat.playerName,
                stackLabel: isLocal
                    ? stackLabel
                    : MoneyFormatting.plain(seat.amountDecimal, currencyCode: tableCurrencyCode),
                isLocalUser: isLocal,
                isLeader: seat.isHost || seat.playerKey == table?.hostPlayerKey
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    if selectedSeat == nil {
                        Text("Tap an open seat")
                            .font(.title3.bold())
                            .foregroundStyle(AppTheme.text)
                    }
                    Text("Table in \(tableCurrencyCode)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                .padding(.horizontal)

                if let table {
                    shareCard(for: table)
                }

                PokerTableSeatLayout(
                    seatCount: SharedTableSeating.seatCount,
                    occupants: layoutOccupants,
                    canStart: selectedSeat != nil && seatedAmount > 0 && !isGameStarted,
                    isStarted: isGameStarted,
                    onSelect: handleSeatTap,
                    onPlay: startGame
                )
                .frame(height: 400)
                .padding(.horizontal)

                if selectedSeat != nil {
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
            resetAmountToFullStack()
        }
        .task {
            await prepareSharedTable()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                await syncSharedTable()
            }
        }
        .sheet(item: $editingAmount) { editor in
            MoneyAmountEditorSheet(editor: editor) { text in
                applyAmountText(text)
            }
            .presentationDetents([.height(420)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSignIn) {
            SignInSheet()
                .modelContext(context)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: showSignIn) { _, isPresented in
            if !isPresented {
                Task { await publishIfPossible() }
            }
        }
    }

    private func shareCard(for table: OpenTableModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    InviteCodeCopyLabel(code: table.inviteCode, style: .headline)
                    Text("Share this link. Friends join the table when they tap it.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }

                Spacer()

                ShareLink(
                    item: TableInviteSharing.url(forInviteCode: table.inviteCode),
                    subject: Text("Join my Pot Master table"),
                    message: Text(TableInviteSharing.message(forInviteCode: table.inviteCode, hostName: table.hostDisplayName))
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.contrastText)
                        .frame(width: 42, height: 42)
                        .background(AppTheme.positive)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Share table")
            }

            if let shareError {
                Text(shareError)
                    .font(.caption)
                    .foregroundStyle(AppTheme.negative)
            } else if SupabaseBootstrap.isConfigured, !SupabaseAuthManager.shared.isSignedIn {
                Button("Sign in so friends can join from the link") {
                    showSignIn = true
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.positive)
            }
        }
        .padding()
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius).stroke(AppTheme.cardBorder))
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

    private func startGame() {
        guard selectedSeat != nil, seatedAmount > 0, !isGameStarted else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            isGameStarted = true
        }
        if let table {
            repo.markStarted(table)
        }
    }

    private func handleSeatTap(_ seat: Int) {
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
        editingAmount = MoneyAmountEditorState(
            id: UUID(),
            currencyCode: tableCurrencyCode,
            text: amountText.isEmpty ? "0" : amountText,
            maximum: Decimal(string: hundredthsText(availableMoney))
        )
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

    private func clampedHundredths(_ value: Double) -> Double {
        let clamped = min(max(value, 0), availableMoney)
        return (clamped * 100).rounded() / 100
    }

    private func hundredthsText(_ value: Double) -> String {
        String(format: "%.2f", clampedHundredths(value))
    }

    private func persistSelectedSeat() {
        guard let table, let selectedSeat else { return }
        do {
            try repo.occupySeat(
                on: table,
                seatNumber: selectedSeat,
                playerName: playerName,
                handle: MemberModel.normalizedHandle(playerHandle),
                amount: seatedAmount
            )
            occupants = table.seats
            shareError = nil
        } catch {
            shareError = error.localizedDescription
            Task { await syncSharedTable() }
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

        if let mine = resolved?.seats.first(where: { $0.playerKey == repo.localPlayerKey }) {
            selectedSeat = mine.seatNumber
            storedSeatNumber = mine.seatNumber
        } else if selectedSeat != nil {
            persistSelectedSeat()
        }

        await publishIfPossible()
        await syncSharedTable()
    }

    private func syncSharedTable() async {
        guard let table else { return }
        if selectedSeat != nil {
            repo.updateLocalAmount(on: table, amount: seatedAmount)
        }
        await repo.refresh(table: table)
        mergeLocalSeat(into: table)
        occupants = table.seats
        isGameStarted = table.isStarted || isGameStarted
        if let mine = table.seats.first(where: { $0.playerKey == repo.localPlayerKey }) {
            selectedSeat = mine.seatNumber
            storedSeatNumber = mine.seatNumber
        }
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
            shareError = error.localizedDescription
        }
    }

    private func publishIfPossible() async {
        guard let table else { return }
        do {
            try await repo.publishForSharing(table)
            shareError = nil
        } catch let error as TableRepositoryError where error == .notSignedIn || error == .cloudUnavailable {
            shareError = nil
        } catch {
            shareError = error.localizedDescription
        }
    }
}

private struct TableSeatOccupant: Equatable {
    var seatNumber: Int
    var playerName: String
    var stackLabel: String
    var isLocalUser: Bool
    var isLeader: Bool
}

private struct PokerTableSeatLayout: View {
    let seatCount: Int
    let occupants: [TableSeatOccupant]
    let canStart: Bool
    let isStarted: Bool
    let onSelect: (Int) -> Void
    let onPlay: () -> Void

    private let seatWidth: CGFloat = 88
    private let seatHeight: CGFloat = 62

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

                TablePlayButton(isEnabled: canStart, isStarted: isStarted, action: onPlay)

                ForEach(1...seatCount, id: \.self) { seat in
                    let occupant = occupants.first { $0.seatNumber == seat }
                    let angle = seatAngle(for: seat)
                    SeatChip(
                        seatNumber: seat,
                        isOccupied: occupant != nil,
                        isLeader: occupant?.isLeader ?? false,
                        playerName: occupant?.playerName ?? "",
                        stackLabel: occupant?.stackLabel ?? "",
                        isTakenByOther: occupant?.isLocalUser == false,
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

private struct TablePlayButton: View {
    let isEnabled: Bool
    let isStarted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Play")
                .font(.headline.weight(.bold))
                .foregroundStyle(isEnabled || isStarted ? AppTheme.contrastText : AppTheme.muted)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(isEnabled || isStarted ? AppTheme.positive : AppTheme.card)
                )
                .overlay(
                    Capsule()
                        .stroke(
                            isEnabled || isStarted ? AppTheme.positive : AppTheme.cardBorder,
                            lineWidth: 2
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(isStarted ? "Game started" : "Play")
        .accessibilityHint(isEnabled ? "Starts the game" : "Sit down to start")
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

private struct SeatChip: View {
    let seatNumber: Int
    let isOccupied: Bool
    let isLeader: Bool
    let playerName: String
    let stackLabel: String
    let isTakenByOther: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                if isOccupied {
                    HStack(spacing: 3) {
                        if isLeader {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(AppTheme.gold)
                        }
                        Text(playerName)
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    Text(stackLabel)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(AppTheme.contrastText.opacity(0.8))
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
                    .fill(isOccupied ? AppTheme.positive : AppTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isOccupied ? AppTheme.positive : AppTheme.cardBorder, lineWidth: isOccupied ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isTakenByOther)
        .accessibilityHint(accessibilityHint)
        .accessibilityLabel(occupancyAccessibilityLabel)
    }

    private var occupancyAccessibilityLabel: String {
        if isOccupied {
            return isLeader ? "\(playerName), party leader" : playerName
        }
        return "Seat \(seatNumber)"
    }

    private var accessibilityHint: String {
        if isTakenByOther {
            return "Seat taken"
        }
        return isOccupied ? "Edits the amount at this seat" : "Sits at this seat"
    }
}
