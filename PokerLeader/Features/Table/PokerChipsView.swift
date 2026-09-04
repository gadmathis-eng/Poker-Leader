import SwiftUI

struct PokerChipDenomination: Identifiable, Hashable {
    let value: Int
    let fill: Color
    let edge: Color
    let text: Color

    var id: Int { value }

    static let standard: [PokerChipDenomination] = [
        PokerChipDenomination(
            value: 1,
            fill: Color(white: 0.95),
            edge: Color(white: 0.55),
            text: Color(white: 0.15)
        ),
        PokerChipDenomination(
            value: 5,
            fill: Color(red: 0.82, green: 0.21, blue: 0.24),
            edge: .white,
            text: .white
        ),
        PokerChipDenomination(
            value: 10,
            fill: Color(red: 0.19, green: 0.42, blue: 0.80),
            edge: .white,
            text: .white
        ),
        PokerChipDenomination(
            value: 25,
            fill: Color(red: 0.15, green: 0.57, blue: 0.35),
            edge: .white,
            text: .white
        ),
        PokerChipDenomination(
            value: 50,
            fill: Color(red: 0.93, green: 0.55, blue: 0.16),
            edge: .white,
            text: .white
        ),
        PokerChipDenomination(
            value: 100,
            fill: Color(white: 0.14),
            edge: .white,
            text: .white
        )
    ]
}

struct PokerChipView: View {
    let denomination: PokerChipDenomination
    var size: CGFloat = 88

    var body: some View {
        ZStack {
            Circle()
                .fill(denomination.fill)

            Circle()
                .strokeBorder(
                    denomination.edge,
                    style: StrokeStyle(
                        lineWidth: size * 0.12,
                        dash: [size * 0.16, size * 0.11]
                    )
                )

            Circle()
                .strokeBorder(denomination.edge.opacity(0.65), lineWidth: 1.5)
                .padding(size * 0.19)

            Text("\(denomination.value)")
                .font(.system(size: size * 0.29, weight: .heavy, design: .rounded))
                .foregroundStyle(denomination.text)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.28), radius: 4, y: 2)
    }
}

struct PokerChipsView: View {
    let seatNumber: Int
    let currencyCode: String

    @State private var chipCounts: [Int: Int] = [:]

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    private var total: Decimal {
        PokerChipDenomination.standard.reduce(into: Decimal(0)) { sum, chip in
            sum += Decimal(chip.value * (chipCounts[chip.value] ?? 0))
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    SectionHeader(title: "Seat \(seatNumber)")
                    Text("Your chips")
                        .font(.title3.bold())
                        .foregroundStyle(AppTheme.text)
                    Text("Tap a chip to add it to your stack")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                .padding(.horizontal)

                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(PokerChipDenomination.standard) { chip in
                        Button {
                            chipCounts[chip.value, default: 0] += 1
                        } label: {
                            VStack(spacing: 6) {
                                PokerChipView(denomination: chip)
                                Text(chipCountLabel(for: chip))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(
                                        (chipCounts[chip.value] ?? 0) > 0 ? AppTheme.positive : AppTheme.muted
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                VStack(spacing: 4) {
                    Text("STACK TOTAL")
                        .font(.caption2.weight(.bold))
                        .tracking(AppTheme.sectionTracking)
                        .foregroundStyle(AppTheme.muted)
                    Text(MoneyFormatting.plain(total, currencyCode: currencyCode))
                        .font(.largeTitle.bold())
                        .foregroundStyle(AppTheme.gold)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(AppTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                        .stroke(AppTheme.cardBorder)
                )
                .padding(.horizontal)

                Button {
                    chipCounts.removeAll()
                } label: {
                    Text("Clear stack")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppTheme.card)
                        .foregroundStyle(total > 0 ? AppTheme.text : AppTheme.muted)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                }
                .buttonStyle(.plain)
                .disabled(total == 0)
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(AppTheme.background)
        .navigationTitle("Chips")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func chipCountLabel(for chip: PokerChipDenomination) -> String {
        let count = chipCounts[chip.value] ?? 0
        return count > 0 ? "×\(count)" : "Tap to add"
    }
}
