import SwiftUI

struct TableSeatSelectionView: View {
    let buyInAmount: Decimal
    let buyInCurrencyCode: String
    let sessionCurrencyCode: String

    @AppStorage("personalTableSeat") private var storedSeatNumber = 0

    @State private var selectedSeat: Int?

    private static let seatCount = 8

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    SectionHeader(title: "Choose your seat")
                        .multilineTextAlignment(.center)
                    Text("Tap an open seat")
                        .font(.title3.bold())
                        .foregroundStyle(AppTheme.text)
                    Text("Your buy-in \(MoneyFormatting.plain(buyInAmount, currencyCode: buyInCurrencyCode)) · table in \(sessionCurrencyCode)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                PokerTableSeatLayout(
                    seatCount: Self.seatCount,
                    selectedSeat: selectedSeat,
                    buyInAmount: buyInAmount,
                    buyInCurrencyCode: buyInCurrencyCode,
                    onSelect: { seat in
                        withAnimation(.easeOut(duration: 0.18)) {
                            selectedSeat = selectedSeat == seat ? nil : seat
                        }
                    }
                )
                .frame(height: 380)
                .padding(.horizontal)

                if let seat = selectedSeat {
                    VStack(spacing: 4) {
                        Text("Seat \(seat)")
                            .font(.headline)
                            .foregroundStyle(AppTheme.text)
                        Text("You're sitting in for \(MoneyFormatting.plain(buyInAmount, currencyCode: buyInCurrencyCode))")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(AppTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                            .stroke(AppTheme.cardBorder)
                    )
                    .padding(.horizontal)
                }

                Button {
                    if let seat = selectedSeat {
                        storedSeatNumber = seat
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
        .onAppear {
            if selectedSeat == nil, storedSeatNumber > 0 {
                selectedSeat = storedSeatNumber
            }
        }
    }

    private var confirmTitle: String {
        guard let seat = selectedSeat else { return "Select a seat" }
        return storedSeatNumber == seat ? "Seated at \(seat)" : "Take seat \(seat)"
    }
}

private struct PokerTableSeatLayout: View {
    let seatCount: Int
    let selectedSeat: Int?
    let buyInAmount: Decimal
    let buyInCurrencyCode: String
    let onSelect: (Int) -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let seatDiameter: CGFloat = 62
            let radiusX = (size.width - seatDiameter) / 2
            let radiusY = (size.height - seatDiameter) / 2

            ZStack {
                TableFelt(
                    potLabel: MoneyFormatting.plain(buyInAmount, currencyCode: buyInCurrencyCode)
                )
                .frame(
                    width: max(size.width - seatDiameter * 1.7, 80),
                    height: max(size.height - seatDiameter * 1.7, 80)
                )

                ForEach(1...seatCount, id: \.self) { seat in
                    let angle = seatAngle(for: seat)
                    SeatChip(
                        seatNumber: seat,
                        isSelected: selectedSeat == seat,
                        action: { onSelect(seat) }
                    )
                    .frame(width: seatDiameter, height: seatDiameter)
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
    let potLabel: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 999)
                .fill(AppTheme.positive.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 999)
                        .stroke(AppTheme.positive.opacity(0.45), lineWidth: 3)
                )

            VStack(spacing: 4) {
                Text("YOUR BUY-IN")
                    .font(.caption2.weight(.bold))
                    .tracking(AppTheme.sectionTracking)
                    .foregroundStyle(AppTheme.muted)
                Text(potLabel)
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.gold)
            }
        }
    }
}

private struct SeatChip: View {
    let seatNumber: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: isSelected ? "person.fill" : "chair.lounge.fill")
                    .font(.system(size: 17, weight: .semibold))
                Text("\(seatNumber)")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(isSelected ? AppTheme.contrastText : AppTheme.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Circle()
                    .fill(isSelected ? AppTheme.positive : AppTheme.card)
            )
            .overlay(
                Circle()
                    .stroke(isSelected ? AppTheme.positive : AppTheme.cardBorder, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
