import SwiftUI
import UIKit

enum TableCenterContent: Equatable {
    case lobby(isPlayEnabled: Bool, inviteCode: String?)
    case waiting(String)
    case pot(title: String, board: [PlayingCard], potLabel: String, status: String)
}

struct TableFeltCaption: Equatable {
    var hostName: String
    var stakes: String
    var seatedCount: Int
}

struct TableSeatOccupant: Equatable {
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

enum PokerTableChrome {
    static let canvas = Color(red: 0.07, green: 0.09, blue: 0.11)
    static let feltTop = Color(red: 0.10, green: 0.40, blue: 0.24)
    static let feltBottom = Color(red: 0.05, green: 0.24, blue: 0.14)
    static let rail = Color(red: 0.16, green: 0.18, blue: 0.21)
    static let railInner = Color(red: 0.22, green: 0.24, blue: 0.27)
    static let sitStroke = Color.white.opacity(0.58)
    static let feltText = Color.white.opacity(0.74)
    static let emptyFill = Color.white.opacity(0.06)
    static let occupiedFill = Color(red: 0.10, green: 0.12, blue: 0.15)
}

struct PokerTableSeatLayout: View {
    let seatCount: Int
    let occupants: [TableSeatOccupant]
    let center: TableCenterContent
    var caption: TableFeltCaption?
    let onSelect: (Int) -> Void
    let onPlay: () -> Void

    private let seatWidth: CGFloat = 84
    private let seatHeight: CGFloat = 86

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let seatSize = CGSize(width: seatWidth, height: seatHeight)

            ZStack {
                PokerTableChrome.canvas

                TableFelt()
                    .padding(.horizontal, seatWidth * 0.20)
                    .padding(.vertical, seatHeight * 0.18)

                feltDecorations
                    .padding(.horizontal, seatWidth * 0.34)
                    .padding(.vertical, seatHeight * 0.62)

                TableCenterView(content: center, onPlay: onPlay)
                    .padding(.horizontal, seatWidth * 1.08)

                ForEach(1...max(seatCount, 1), id: \.self) { seat in
                    let occupant = occupants.first { $0.seatNumber == seat }
                    SeatChip(
                        seatNumber: seat,
                        occupant: occupant,
                        action: { onSelect(seat) }
                    )
                    .frame(width: seatWidth, height: seatHeight)
                    .position(
                        PokerTableSeatGeometry.center(
                            forSeat: seat,
                            of: seatCount,
                            in: size,
                            seatSize: seatSize
                        )
                    )
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var feltDecorations: some View {
        VStack(spacing: 8) {
            seatedCountPill

            Spacer(minLength: 0)

            if showsFeltCaption, let caption {
                VStack(spacing: 3) {
                    Text(feltHostLine(caption.hostName))
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                    if !caption.stakes.isEmpty {
                        Text(caption.stakes)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    Text("POT MASTER")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.4)
                        .opacity(0.55)
                }
                .foregroundStyle(PokerTableChrome.feltText)
                .multilineTextAlignment(.center)
            }
        }
    }

    private var showsFeltCaption: Bool {
        if case .pot = center { return false }
        return caption != nil
    }

    private var seatedCountPill: some View {
        Text("\(caption?.seatedCount ?? occupants.count)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.white.opacity(0.86))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.black.opacity(0.28)))
            .overlay(Capsule().stroke(Color.white.opacity(0.12)))
            .accessibilityLabel("\(caption?.seatedCount ?? occupants.count) seated")
    }

    private func feltHostLine(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || MemberModel.isPlaceholderName(trimmed) {
            return "HOST"
        }
        return "HOST · \(trimmed.uppercased())"
    }
}

private struct TableFelt: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 78, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [PokerTableChrome.feltTop, PokerTableChrome.feltBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 78, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.07), Color.clear],
                            center: .center,
                            startRadius: 8,
                            endRadius: 180
                        )
                    )
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 70, style: .continuous)
                    .stroke(Color.black.opacity(0.22), lineWidth: 10)
                    .padding(11)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 78, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                PokerTableChrome.railInner,
                                PokerTableChrome.rail,
                                Color.black.opacity(0.55)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 16
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 72, style: .continuous)
                    .stroke(AppTheme.positive.opacity(0.22), lineWidth: 2)
                    .padding(8)
            }
            .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
    }
}

private struct TableCenterView: View {
    let content: TableCenterContent
    let onPlay: () -> Void

    var body: some View {
        switch content {
        case .lobby(let isEnabled, let inviteCode):
            TableLobbyCard(isPlayEnabled: isEnabled, inviteCode: inviteCode, onPlay: onPlay)
        case .waiting(let text):
            Text(text)
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppTheme.card.opacity(0.94))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.cardBorder)
                )
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
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .fill(AppTheme.card.opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .stroke(AppTheme.gold.opacity(0.5), lineWidth: 2)
            )
            .accessibilityElement(children: .combine)
        }
    }
}

private struct TableLobbyCard: View {
    let isPlayEnabled: Bool
    let inviteCode: String?
    let onPlay: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "clock")
                Text("Waiting for others")
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(AppTheme.text)

            Text(
                isPlayEnabled
                    ? "Share this table with your friends, then deal."
                    : "Tap SIT to take a seat, then share the table."
            )
            .font(.caption2)
            .foregroundStyle(AppTheme.muted)
            .multilineTextAlignment(.center)

            VStack(spacing: 7) {
                if let inviteCode, !inviteCode.isEmpty {
                    TableLobbyCopyButton(code: inviteCode)
                }
                TablePlayButton(isEnabled: isPlayEnabled, action: onPlay)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 188)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.card.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.cardBorder)
        )
    }
}

private struct TableLobbyCopyButton: View {
    let code: String
    @State private var didCopy = false

    var body: some View {
        Button(action: copyCode) {
            Text(didCopy ? "Copied" : "Copy code")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(AppTheme.positive)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            AppTheme.positive,
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(didCopy ? "Copied table code" : "Copy table code")
    }

    private func copyCode() {
        UIPasteboard.general.string = code
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
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
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isEnabled ? AppTheme.positive : AppTheme.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
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

private struct SeatChip: View {
    let seatNumber: Int
    let occupant: TableSeatOccupant?
    let action: () -> Void

    private var isOccupied: Bool { occupant != nil }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                seatBody

                if occupant?.isDealer == true {
                    Text("D")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(AppTheme.contrastText)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(AppTheme.gold))
                        .offset(x: -4, y: -5)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(occupant?.isLocalUser == false)
        .accessibilityHint(accessibilityHint)
        .accessibilityLabel(occupancyAccessibilityLabel)
    }

    @ViewBuilder
    private var seatBody: some View {
        if let occupant {
            occupiedSeat(occupant)
        } else {
            emptySeat
        }
    }

    private var emptySeat: some View {
        VStack(spacing: 2) {
            Text("SIT")
                .font(.caption.weight(.heavy))
                .tracking(1)
            Text("\(seatNumber)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.white.opacity(0.7))
        }
        .foregroundStyle(Color.white.opacity(0.9))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PokerTableChrome.emptyFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    PokerTableChrome.sitStroke,
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                )
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 14)
    }

    private func occupiedSeat(_ occupant: TableSeatOccupant) -> some View {
        VStack(spacing: 1) {
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
                .foregroundStyle(stackColor(for: occupant))
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
                    .foregroundStyle(Color.white.opacity(0.7))
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
        }
        .foregroundStyle(nameColor(for: occupant))
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(fillColor(for: occupant))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(strokeColor(for: occupant), lineWidth: strokeWidth(for: occupant))
        )
        .opacity(occupant.isFolded ? 0.55 : 1)
    }

    private func fillColor(for occupant: TableSeatOccupant) -> Color {
        if occupant.isFolded { return AppTheme.muted.opacity(0.7) }
        if occupant.isLocalUser { return AppTheme.positive }
        return PokerTableChrome.occupiedFill
    }

    private func nameColor(for occupant: TableSeatOccupant) -> Color {
        occupant.isLocalUser ? AppTheme.contrastText : Color.white
    }

    private func stackColor(for occupant: TableSeatOccupant) -> Color {
        occupant.isLocalUser ? AppTheme.contrastText.opacity(0.8) : Color.white.opacity(0.78)
    }

    private func strokeColor(for occupant: TableSeatOccupant) -> Color {
        if occupant.isActing || occupant.isWinner {
            return AppTheme.gold
        }
        return occupant.isLocalUser ? AppTheme.positive : Color.white.opacity(0.16)
    }

    private func strokeWidth(for occupant: TableSeatOccupant) -> CGFloat {
        occupant.isActing || occupant.isWinner ? 3 : 1.5
    }

    private var occupancyAccessibilityLabel: String {
        guard let occupant else { return "Seat \(seatNumber), sit" }
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
