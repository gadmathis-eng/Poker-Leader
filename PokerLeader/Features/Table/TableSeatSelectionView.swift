import SwiftUI

struct TableSeatSelectionView: View {
    let buyInAmount: Decimal
    let buyInCurrencyCode: String
    let sessionCurrencyCode: String

    @AppStorage("displayName") private var displayName = "Your name"
    @AppStorage("playerHandle") private var playerHandle = "@yourname"
    @AppStorage("personalTableSeat") private var storedSeatNumber = 0

    @State private var selectedSeat: Int?
    @State private var amountText = ""
    @State private var editingAmount: MoneyAmountEditorState?

    private static let seatCount = 8
    private static let amountStep = 0.01

    private var playerName: String {
        if !MemberModel.isPlaceholderName(displayName) {
            return displayName
        }
        return MemberModel.normalizedHandle(playerHandle) ?? "You"
    }

    private var tableBuyInAmount: Decimal {
        TableCurrencyConversion.amountInTableCurrency(
            buyInAmount,
            from: buyInCurrencyCode,
            to: sessionCurrencyCode
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
        MoneyFormatting.plain(seatedAmount, currencyCode: sessionCurrencyCode)
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
                    Text("Table in \(sessionCurrencyCode)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                .padding(.horizontal)

                PokerTableSeatLayout(
                    seatCount: Self.seatCount,
                    selectedSeat: selectedSeat,
                    playerName: playerName,
                    stackLabel: stackLabel,
                    onSelect: handleSeatTap
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
        .onAppear {
            if selectedSeat == nil, storedSeatNumber > 0 {
                selectedSeat = storedSeatNumber
            }
            resetAmountToFullStack()
        }
        .sheet(item: $editingAmount) { editor in
            MoneyAmountEditorSheet(editor: editor) { text in
                applyAmountText(text)
            }
            .presentationDetents([.height(420)])
            .presentationDragIndicator(.visible)
        }
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
                    Text(MoneyFormatting.plain(0, currencyCode: sessionCurrencyCode))
                    Spacer()
                    Text(MoneyFormatting.plain(tableBuyInAmount, currencyCode: sessionCurrencyCode))
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

    private func handleSeatTap(_ seat: Int) {
        if selectedSeat == seat {
            presentAmountEditor()
            return
        }

        withAnimation(.easeOut(duration: 0.18)) {
            selectedSeat = seat
            storedSeatNumber = seat
            resetAmountToFullStack()
        }
    }

    private func presentAmountEditor() {
        guard hasMoney else { return }
        editingAmount = MoneyAmountEditorState(
            id: UUID(),
            currencyCode: sessionCurrencyCode,
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
    }

    private func clampedHundredths(_ value: Double) -> Double {
        let clamped = min(max(value, 0), availableMoney)
        return (clamped * 100).rounded() / 100
    }

    private func hundredthsText(_ value: Double) -> String {
        String(format: "%.2f", clampedHundredths(value))
    }
}

private struct PokerTableSeatLayout: View {
    let seatCount: Int
    let selectedSeat: Int?
    let playerName: String
    let stackLabel: String
    let onSelect: (Int) -> Void

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

                ForEach(1...seatCount, id: \.self) { seat in
                    let angle = seatAngle(for: seat)
                    SeatChip(
                        seatNumber: seat,
                        isOccupied: selectedSeat == seat,
                        playerName: playerName,
                        stackLabel: stackLabel,
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
    let playerName: String
    let stackLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                if isOccupied {
                    Text(playerName)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
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
        .accessibilityHint(isOccupied ? "Edits the amount at this seat" : "Sits at this seat")
    }
}
