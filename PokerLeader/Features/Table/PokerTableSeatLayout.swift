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
    /// What tapping your own seat does right now.
    var tapHint: String?
    var isLeader: Bool
    var isDealer: Bool
    var isActing: Bool
    var isFolded: Bool
    var isWinner: Bool
}

enum PokerTableChrome {
    static let canvas = Color.black
    static let feltTop = Color(red: 0.10, green: 0.40, blue: 0.24)
    static let feltBottom = Color(red: 0.05, green: 0.24, blue: 0.14)
    static let rail = Color(red: 0.16, green: 0.18, blue: 0.21)
    static let railInner = Color(red: 0.22, green: 0.24, blue: 0.27)
    static let sitStroke = Color.white.opacity(0.58)
    static let feltText = Color.white.opacity(0.74)
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
    private let seatHeight: CGFloat = 92

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let seatSize = CGSize(width: seatWidth, height: seatHeight)

            ZStack {
                PokerTableChrome.canvas

                TableFelt()
                    .padding(.horizontal, PokerTableSeatGeometry.feltInsets(seatSize: seatSize).width)
                    .padding(.vertical, PokerTableSeatGeometry.feltInsets(seatSize: seatSize).height)

                feltDecorations
                    .padding(.horizontal, seatWidth * 0.34)
                    .padding(.vertical, seatHeight * 0.62)

                TableCenterView(content: center, onPlay: onPlay)
                    .padding(.horizontal, seatWidth * 1.08)

                ForEach(1...max(seatCount, 1), id: \.self) { seat in
                    let occupant = occupants.first { $0.seatNumber == seat }
                    let spot = PokerTableSeatGeometry.center(
                        forSeat: seat,
                        of: seatCount,
                        in: size,
                        seatSize: seatSize
                    )
                    SeatMarker(
                        seatNumber: seat,
                        occupant: occupant,
                        // Near-side seats read outwards, so every player's cards land on the felt.
                        // The side seats sit exactly halfway down, so they need to stay clear of
                        // the cut-off rather than flip on a rounding error.
                        isMirrored: spot.y > size.height * 0.55,
                        action: { onSelect(seat) }
                    )
                    .frame(width: seatWidth, height: seatHeight)
                    .position(spot)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        GeometryReader { proxy in
            let radius = PokerTableSeatGeometry.cornerRadius(
                for: CGRect(origin: .zero, size: proxy.size)
            )
            let innerRadius = max(radius - 8, 10)
            let grooveRadius = max(radius - 6, 12)

            RoundedRectangle(cornerRadius: radius, style: .circular)
                .fill(
                    LinearGradient(
                        colors: [PokerTableChrome.feltTop, PokerTableChrome.feltBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .circular)
                        .fill(
                            RadialGradient(
                                colors: [Color.white.opacity(0.07), Color.clear],
                                center: .center,
                                startRadius: 8,
                                endRadius: min(proxy.size.width, proxy.size.height) * 0.55
                            )
                        )
                        .allowsHitTesting(false)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: innerRadius, style: .circular)
                        .stroke(Color.black.opacity(0.22), lineWidth: 10)
                        .padding(11)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .circular)
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
                    RoundedRectangle(cornerRadius: grooveRadius, style: .circular)
                        .stroke(AppTheme.positive.opacity(0.22), lineWidth: 2)
                        .padding(8)
                }
                .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
        }
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
                BoardCardsView(cards: board, size: .table)
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
        .frame(maxWidth: 210)
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

/// A seat on the rail: a dashed ring when it is open, a name disc when someone is in it.
private struct SeatMarker: View {
    let seatNumber: Int
    let occupant: TableSeatOccupant?
    /// Stacks the seat the other way up, for players sitting on the near side of the table.
    var isMirrored = false
    let action: () -> Void

    private let discSize: CGFloat = 30

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                if let occupant {
                    if isMirrored {
                        handRow(for: occupant)
                        stackText(for: occupant)
                        nameText(for: occupant)
                        disc(for: occupant)
                    } else {
                        disc(for: occupant)
                        nameText(for: occupant)
                        stackText(for: occupant)
                        handRow(for: occupant)
                    }
                } else {
                    openSeat
                }
            }
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .opacity(occupant?.isFolded == true ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(occupant?.isLocalUser == false)
        .accessibilityHint(accessibilityHint)
        .accessibilityLabel(occupancyAccessibilityLabel)
    }

    private var openSeat: some View {
        VStack(spacing: 3) {
            Text("\(seatNumber)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.7))
                .frame(width: discSize, height: discSize)
                .overlay(
                    Circle().strokeBorder(
                        PokerTableChrome.sitStroke,
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
                )
            Text("SIT")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1)
                .foregroundStyle(Color.white.opacity(0.9))
        }
    }

    private func disc(for occupant: TableSeatOccupant) -> some View {
        Text(CircleRepository.initial(for: occupant.playerName))
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(initialColor(for: occupant))
            .frame(width: discSize, height: discSize)
            .background(
                Circle()
                    .fill(fillColor(for: occupant))
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            )
            .overlay(
                Circle().strokeBorder(strokeColor(for: occupant), lineWidth: isHighlighted(occupant) ? 2 : 1)
            )
            .overlay(
                Circle()
                    .stroke(AppTheme.gold.opacity(0.3), lineWidth: 2)
                    .scaleEffect(1.28)
                    .opacity(occupant.isActing ? 1 : 0)
            )
            .overlay(alignment: .topLeading) {
                if occupant.isLeader {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(AppTheme.gold)
                        .offset(x: -1, y: -1)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if occupant.isDealer {
                    dealerButton
                }
            }
    }

    private var dealerButton: some View {
        Text("D")
            .font(.system(size: 8, weight: .heavy))
            .foregroundStyle(AppTheme.contrastText)
            .frame(width: 14, height: 14)
            .background(Circle().fill(AppTheme.gold))
            .offset(x: 2, y: 1)
            .accessibilityHidden(true)
    }

    private func nameText(for occupant: TableSeatOccupant) -> some View {
        Text(occupant.playerName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isHighlighted(occupant) ? AppTheme.gold : Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private func stackText(for occupant: TableSeatOccupant) -> some View {
        Text(occupant.stackLabel)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.white.opacity(0.78))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    /// The cards still in front of a player, or what they have put in the pot.
    @ViewBuilder
    private func handRow(for occupant: TableSeatOccupant) -> some View {
        if occupant.isFolded {
            Text("Folded")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.7))
        } else if !occupant.cards.isEmpty || occupant.faceDownCount > 0 || occupant.committedLabel != nil {
            HStack(spacing: 4) {
                if !occupant.cards.isEmpty || occupant.faceDownCount > 0 {
                    CardRowView(
                        cards: occupant.cards,
                        faceDownCount: occupant.faceDownCount,
                        size: .seat
                    )
                }
                if let committedLabel = occupant.committedLabel {
                    HStack(spacing: 2) {
                        Circle()
                            .fill(AppTheme.gold)
                            .frame(width: 4, height: 4)
                        Text(committedLabel)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(AppTheme.gold)
                }
            }
        }
    }

    private func isHighlighted(_ occupant: TableSeatOccupant) -> Bool {
        occupant.isActing || occupant.isWinner
    }

    private func fillColor(for occupant: TableSeatOccupant) -> Color {
        if occupant.isFolded { return AppTheme.muted.opacity(0.7) }
        if occupant.isLocalUser { return AppTheme.positive }
        return PokerTableChrome.occupiedFill
    }

    private func initialColor(for occupant: TableSeatOccupant) -> Color {
        occupant.isLocalUser ? AppTheme.contrastText : Color.white
    }

    private func strokeColor(for occupant: TableSeatOccupant) -> Color {
        if isHighlighted(occupant) {
            return AppTheme.gold
        }
        return occupant.isLocalUser ? AppTheme.positive : Color.white.opacity(0.24)
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
        if let occupant {
            return occupant.tapHint ?? "Your buy-in. Chosen before you sat down."
        }
        return "Sits at this seat"
    }
}
