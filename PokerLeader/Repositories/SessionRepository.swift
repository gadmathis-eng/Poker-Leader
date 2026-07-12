import Foundation
import SwiftData

@MainActor
final class SessionRepository {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func setupSession(for circle: CircleModel) -> SessionModel? {
        circle.sessions.first { $0.status == .setup }
    }

    func saveSetupSession(
        existing session: SessionModel?,
        circle: CircleModel,
        title: String,
        buyInAmount: Decimal,
        currencyCode: String,
        playerMembers: [MemberModel],
        playerTotals: [UUID: Decimal]
    ) -> SessionModel {
        let safeBuyInAmount = buyInAmount.clampedToNonNegative
        let safePlayerTotals = playerTotals.mapValues(\.clampedToNonNegative)
        let session = session ?? setupSession(for: circle) ?? SessionModel(
            title: title,
            status: .setup,
            buyInAmount: safeBuyInAmount,
            currencyCode: circle.currencyCode
        )

        if session.circle == nil {
            session.circle = circle
            circle.sessions.append(session)
        }

        if session.modelContext == nil {
            context.insert(session)
        }

        let safeCurrencyCode = CurrencyPreferences.normalizedCurrencyCode(currencyCode)

        session.title = title
        session.status = .setup
        session.buyInAmount = safeBuyInAmount
        session.currencyCode = safeCurrencyCode
        circle.currencyCode = safeCurrencyCode
        updateSetupPlayers(
            for: session,
            with: playerMembers,
            playerTotals: safePlayerTotals,
            buyInAmount: safeBuyInAmount
        )
        session.potTotal = session.players.reduce(0) { $0 + $1.totalIn }
        try? context.save()
        sync(session)
        return session
    }

    func start(session: SessionModel) {
        session.status = .live
        session.startedAt = .now
        try? context.save()
        sync(session)
    }

    func createLiveSession(circle: CircleModel, title: String, playerMembers: [MemberModel]) -> SessionModel {
        let session = SessionModel(
            title: title,
            status: .live,
            buyInAmount: circle.defaultBuyIn.clampedToNonNegative,
            currencyCode: circle.currencyCode
        )
        session.circle = circle

        for member in playerMembers {
            let player = SessionPlayerModel(
                displayName: member.displayName(preferredHandle: currentUserHandle),
                initial: member.initial,
                memberId: member.id
            )
            player.session = session
            session.players.append(player)
            context.insert(player)
        }

        context.insert(session)
        circle.sessions.append(session)
        try? context.save()
        sync(session)
        return session
    }

    private func updateSetupPlayers(
        for session: SessionModel,
        with members: [MemberModel],
        playerTotals: [UUID: Decimal],
        buyInAmount: Decimal
    ) {
        let selectedMemberIds = Set(members.map(\.id))

        for player in session.players where player.memberId.map({ !selectedMemberIds.contains($0) }) ?? true {
            context.delete(player)
        }
        session.players.removeAll { player in
            player.memberId.map { !selectedMemberIds.contains($0) } ?? true
        }

        for member in members {
            if let player = session.players.first(where: { $0.memberId == member.id }) {
                player.displayName = member.displayName(preferredHandle: currentUserHandle)
                player.initial = member.initial
                updateSetupMoney(for: player, totalIn: playerTotals[member.id] ?? 0, buyInAmount: buyInAmount)
                continue
            }

            let player = SessionPlayerModel(
                displayName: member.displayName(preferredHandle: currentUserHandle),
                initial: member.initial,
                memberId: member.id
            )
            player.session = session
            updateSetupMoney(for: player, totalIn: playerTotals[member.id] ?? 0, buyInAmount: buyInAmount)
            session.players.append(player)
            context.insert(player)
        }
    }

    private func updateSetupMoney(for player: SessionPlayerModel, totalIn: Decimal, buyInAmount: Decimal) {
        let safeTotalIn = totalIn.clampedToNonNegative
        let safeBuyInAmount = buyInAmount.clampedToNonNegative
        player.totalIn = safeTotalIn
        guard safeBuyInAmount > 0 else {
            player.buyInCount = 0
            return
        }

        let rawCount = NSDecimalNumber(decimal: safeTotalIn / safeBuyInAmount)
        player.buyInCount = max(0, rawCount.rounding(accordingToBehavior: nil).intValue)
    }

    private var currentUserHandle: String {
        UserDefaults.standard.string(forKey: "playerHandle") ?? "@yourname"
    }

    func addBuyIn(player: SessionPlayerModel, amount: Decimal, session: SessionModel) {
        let safeAmount = amount.clampedToNonNegative
        guard safeAmount > 0 else { return }
        player.buyInCount += 1
        player.totalIn += safeAmount
        session.potTotal = session.players.reduce(0) { $0 + $1.totalIn }
        try? context.save()
        sync(session)
    }

    func removeBuyIn(player: SessionPlayerModel, amount: Decimal, session: SessionModel) {
        let safeAmount = amount.clampedToNonNegative
        guard safeAmount > 0, player.buyInCount > 0 || player.totalIn > 0 else { return }
        player.buyInCount -= 1
        player.totalIn = (player.totalIn - safeAmount).clampedToNonNegative
        session.potTotal = session.players.reduce(0) { $0 + $1.totalIn }
        try? context.save()
        sync(session)
    }

    func updateTotalIn(player: SessionPlayerModel, amount: Decimal, session: SessionModel) {
        updateSetupMoney(for: player, totalIn: amount, buyInAmount: session.buyInAmount)
        session.potTotal = session.players.reduce(0) { $0 + $1.totalIn }
        try? context.save()
        sync(session)
    }

    func updateFinalOut(player: SessionPlayerModel, amount: Decimal) {
        player.finalOut = amount.clampedToNonNegative
        try? context.save()
        if let session = player.session {
            sync(session)
        }
    }

    func settle(session: SessionModel) {
        let nets = SettlementService.computeNets(players: session.players)
        for player in session.players {
            if let entry = nets.first(where: { $0.id == player.id }) {
                player.net = entry.net
            }
        }
        let payments = SettlementService.minimumPayments(nets: nets)
        session.payments.removeAll()
        for p in payments {
            let model = SettlementPaymentModel(
                fromInitial: p.fromInitial,
                fromName: p.fromName,
                toInitial: p.toInitial,
                toName: p.toName,
                amount: p.amount.clampedToNonNegative
            )
            model.session = session
            session.payments.append(model)
            context.insert(model)
        }
        session.status = .settled
        session.endedAt = .now
        session.summaryLine = nets.first.map { "\($0.name) \(MoneyFormatting.format($0.net, currencyCode: session.currencyCode))" }
        if let circle = session.circle {
            circle.gameCount += 1
            circle.lastPlayedAt = .now
        }
        try? context.save()
        createGamePlayedNotification(for: session)
        sync(session)
    }

    private func createGamePlayedNotification(for session: SessionModel) {
        guard let circle = session.circle else { return }
        let memberIds = Set(circle.members.filter(\.isCurrentUser).map(\.id))
        guard let player = session.players.first(where: { player in
            guard let memberId = player.memberId else { return false }
            return memberIds.contains(memberId)
        }) else {
            return
        }

        NotificationRepository(context: context).createGamePlayedNotificationIfNeeded(
            session: session,
            net: player.net ?? 0,
            circleName: circle.name
        )
    }

    private func sync(_ session: SessionModel) {
        Task {
            try? await SupabaseSyncService.shared.upsertSession(session)
        }
    }
}
