import SwiftUI

struct TableSeatSelectionView: View {
    let buyInAmount: Decimal
    let buyInCurrencyCode: String
    let sessionCurrencyCode: String

    @AppStorage("displayName") private var displayName = "Your name"
    @AppStorage("playerHandle") private var playerHandle = "@yourname"
    @AppStorage("personalTableSeat") private var storedSeatNumber = 0

    @State private var selectedSeat: Int?
    @State private var seatedAt: Int?

    private static let seatCount = 8

    private var playerName: String {
        if !MemberModel.isPlaceholderName(displayName) {
            return displayName
        }
        return MemberModel.normalizedHandle(playerHandle) ?? "You"
    }

    private var stackLabel: String {
        MoneyFormatting.plain(buyInAmount, currencyCode: buyInCurrencyCode)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    SectionHeader(title: "Choose your seat")
                    Text("Tap an open seat")
                        .font(.title3.bold())
                        .foregroundStyle(AppTheme.text)
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
                    onSelect: { seat in
                        withAnimation(.easeOut(duration: 0.18)) {
                            selectedSeat = selectedSeat == seat ? nil : seat
                        }
                    }
                )
                .frame(height: 400)
                .padding(.horizontal)

                Button {
                    if let seat = selectedSeat {
                        storedSeatNumber = seat
                        seatedAt = seat
                    }
                } label: {
                    Text(confirmTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedSeat == nil ? AppTheme.card : AppTheme.positive)
                        .foregroundStyle(selectedSeat == nil ? AppTheme.muted : AppTheme.contrastText)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                }
                .buttonStyle(.plain)
                .disabled(selectedSeat == nil)
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(AppTheme.background)
        .navigationTitle("Table")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $seatedAt) { seat in
            PokerChipsView(seatNumber: seat, currencyCode: buyInCurrencyCode)
        }
    }

    private var confirmTitle: String {
        guard let seat = selectedSeat else { return "Select a seat" }
        return "Take seat \(seat)"
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
    }
}
