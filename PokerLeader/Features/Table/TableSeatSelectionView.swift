import SwiftUI

struct TableSeatSelectionView: View {
    let buyInAmount: Decimal
    let buyInCurrencyCode: String
    let sessionCurrencyCode: String

    @AppStorage("displayName") private var displayName = "Your name"
    @AppStorage("playerHandle") private var playerHandle = "@yourname"

    @State private var party = TableParty()
    @State private var pendingGuestSeat: Int?
    @State private var guestName = ""

    private static let seatCount = 8

    private var playerName: String {
        if !MemberModel.isPlaceholderName(displayName) {
            return displayName
        }
        return MemberModel.normalizedHandle(playerHandle) ?? "You"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                PokerTableSeatLayout(
                    seatCount: Self.seatCount,
                    party: party,
                    currencyCode: buyInCurrencyCode,
                    onSelectSeat: handleSeatTap
                )
                .frame(height: 400)
                .padding(.horizontal)

                partyRoster

                actionButtons
            }
            .padding(.vertical)
        }
        .background(AppTheme.background)
        .navigationTitle("Table")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Add player", isPresented: guestPromptBinding) {
            TextField("Name", text: $guestName)
            Button("Cancel", role: .cancel) { pendingGuestSeat = nil }
            Button("Join") { addGuest() }
        } message: {
            if let seat = pendingGuestSeat {
                Text("Seat \(seat)")
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            SectionHeader(title: party.isStarted ? "Game in progress" : "Table lobby")
            Text(headerTitle)
                .font(.title3.bold())
                .foregroundStyle(AppTheme.text)
            Text(headerSubtitle)
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }

    private var headerTitle: String {
        if party.isStarted { return "Good luck" }
        return party.you == nil ? "Tap an open seat" : "Waiting to start"
    }

    private var headerSubtitle: String {
        if let leader = party.leader {
            let leaderLabel = leader.isYou ? "You are" : "\(leader.name) is"
            return "\(leaderLabel) party leader · table in \(sessionCurrencyCode)"
        }
        return "First to sit down creates the game · table in \(sessionCurrencyCode)"
    }

    @ViewBuilder
    private var partyRoster: some View {
        if !party.players.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Party · \(party.players.count) seated")

                VStack(spacing: 0) {
                    ForEach(Array(party.players.enumerated()), id: \.element.id) { index, player in
                        if index > 0 {
                            Divider().overlay(AppTheme.cardBorder)
                        }
                        rosterRow(for: player, joinPosition: index + 1)
                    }
                }
                .background(AppTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                        .stroke(AppTheme.cardBorder)
                )
            }
            .padding(.horizontal)
        }
    }

    private func rosterRow(for player: TablePartyPlayer, joinPosition: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(joinPosition)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(AppTheme.muted)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(player.isYou ? "\(player.name) (you)" : player.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.text)

                    if party.isLeader(player.id) {
                        Label("Leader", systemImage: "crown.fill")
                            .labelStyle(.iconOnly)
                            .font(.caption2)
                            .foregroundStyle(AppTheme.gold)
                    }
                }
                Text("Seat \(player.seat) · \(MoneyFormatting.plain(player.stack, currencyCode: buyInCurrencyCode))")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.muted)
            }

            Spacer(minLength: 0)

            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    party.leave(player.id)
                }
            } label: {
                Text("Leave")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.negative)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.negative.opacity(0.12))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
    }

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 10) {
            if party.isStarted {
                Text("Game started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(AppTheme.positive.opacity(0.15))
                    .foregroundStyle(AppTheme.positive)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            } else if party.youAreLeader {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        party.startGame()
                    }
                } label: {
                    Text(startButtonTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(party.canStart ? AppTheme.positive : AppTheme.card)
                        .foregroundStyle(party.canStart ? AppTheme.contrastText : AppTheme.muted)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                }
                .buttonStyle(.plain)
                .disabled(!party.canStart)
            } else if let leader = party.leader {
                Text("Waiting for \(leader.name) to start")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(AppTheme.card)
                    .foregroundStyle(AppTheme.muted)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }
        }
        .padding(.horizontal)
    }

    private var startButtonTitle: String {
        guard !party.canStart else { return "Start game" }
        let needed = TableParty.minimumPlayersToStart - party.players.count
        return needed == 1 ? "Need 1 more player" : "Need \(needed) more players"
    }

    private var guestPromptBinding: Binding<Bool> {
        Binding(
            get: { pendingGuestSeat != nil },
            set: { if !$0 { pendingGuestSeat = nil } }
        )
    }

    private func handleSeatTap(_ seat: Int) {
        guard party.player(inSeat: seat) == nil else { return }

        if party.you == nil {
            withAnimation(.easeOut(duration: 0.18)) {
                party.join(name: playerName, seat: seat, stack: buyInAmount, isYou: true)
            }
            return
        }

        guestName = "Player \(party.players.count + 1)"
        pendingGuestSeat = seat
    }

    private func addGuest() {
        guard let seat = pendingGuestSeat else { return }
        let trimmed = guestName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Player \(party.players.count + 1)" : trimmed

        withAnimation(.easeOut(duration: 0.18)) {
            party.join(name: name, seat: seat, stack: buyInAmount)
        }
        pendingGuestSeat = nil
    }
}

private struct PokerTableSeatLayout: View {
    let seatCount: Int
    let party: TableParty
    let currencyCode: String
    let onSelectSeat: (Int) -> Void

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
                    let occupant = party.player(inSeat: seat)

                    SeatChip(
                        seatNumber: seat,
                        occupant: occupant,
                        isLeader: occupant.map { party.isLeader($0.id) } ?? false,
                        currencyCode: currencyCode,
                        action: { onSelectSeat(seat) }
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
    let occupant: TablePartyPlayer?
    let isLeader: Bool
    let currencyCode: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                if let occupant {
                    HStack(spacing: 3) {
                        if isLeader {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(AppTheme.gold)
                        }
                        Text(occupant.name)
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    Text(MoneyFormatting.plain(occupant.stack, currencyCode: currencyCode))
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
            .foregroundStyle(occupant == nil ? AppTheme.text : AppTheme.contrastText)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(occupant == nil ? AppTheme.card : AppTheme.positive)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isLeader ? AppTheme.gold : (occupant == nil ? AppTheme.cardBorder : AppTheme.positive),
                        lineWidth: isLeader ? 2.5 : (occupant == nil ? 1 : 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
