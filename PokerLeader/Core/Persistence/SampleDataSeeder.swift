import Foundation
import SwiftData

enum SampleDataSeeder {
    private static let seededKey = "didSeedSampleData"

    static func seedIfNeeded(context: ModelContext) {
        guard !SupabaseBootstrap.isConfigured else { return }
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }

        let me = MemberModel(displayName: "Your name", initial: "Y", handle: "@yourname", isCurrentUser: true)

        let uniBoys = CircleModel(
            name: "Uni Boys",
            shortCode: "UB",
            defaultBuyIn: 20,
            memberCount: 5,
            gameCount: 22,
            lastPlayedAt: Calendar.current.date(byAdding: .day, value: -1, to: .now)
        )
        let membersUB = [
            MemberModel(displayName: "Alex", initial: "A", handle: "@alexplaysaces"),
            MemberModel(displayName: "Ben", initial: "B", handle: "@bigblindben"),
            MemberModel(displayName: "Josh", initial: "J", handle: "@joshjams"),
            MemberModel(displayName: "Max", initial: "M", handle: "@maxvalue"),
            MemberModel(displayName: "Dan", initial: "D", handle: "@danger_dan"),
            me
        ]
        membersUB.forEach { $0.circle = uniBoys; context.insert($0) }
        uniBoys.members = membersUB
        uniBoys.memberCount = membersUB.count

        let london = CircleModel(
            name: "London Poker Night",
            shortCode: "LP",
            defaultBuyIn: 20,
            memberCount: 4,
            gameCount: 14,
            lastPlayedAt: Calendar.current.date(byAdding: .day, value: -3, to: .now)
        )
        [
            ("Ace", "A", "@ace"),
            ("Lucky", "L", "@lucky"),
            ("Stacks", "S", "@stacks"),
            ("King", "K", "@king")
        ].forEach { name, initial, handle in
            let m = MemberModel(displayName: name, initial: initial, handle: handle)
            m.circle = london
            london.members.append(m)
            context.insert(m)
        }

        let work = CircleModel(
            name: "Work Poker",
            shortCode: "WP",
            defaultBuyIn: 20,
            memberCount: 6,
            gameCount: 9,
            lastPlayedAt: Calendar.current.date(byAdding: .day, value: -14, to: .now)
        )

        context.insert(uniBoys)
        context.insert(london)
        context.insert(work)
        CircleCreatorStore.markCreator(uniBoys.id)
        CircleCreatorStore.markCreator(london.id)
        CircleCreatorStore.markCreator(work.id)

        seedSettledSession(
            context: context,
            circle: uniBoys,
            title: uniBoys.name,
            daysAgo: 5,
            yourNet: 80,
            players: [
                ("Alex", "A", 100, 180, 80),
                ("Ben", "B", 50, 0, -50),
                ("Josh", "J", 50, 100, 50),
                ("Max", "M", 150, 70, -80)
            ]
        )

        try? context.save()
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    private static func seedSettledSession(
        context: ModelContext,
        circle: CircleModel,
        title: String,
        daysAgo: Int,
        yourNet: Decimal,
        players: [(String, String, Decimal, Decimal, Decimal)]
    ) {
        let session = SessionModel(
            title: title,
            status: .settled,
            buyInAmount: 20,
            potTotal: players.reduce(0) { $0 + $1.2 },
            startedAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now,
            endedAt: .now,
            summaryLine: "Alex +£80 · Max took the hit"
        )
        session.circle = circle

        for (name, initial, totalIn, finalOut, net) in players {
            let count = Int(truncating: (totalIn / 20) as NSDecimalNumber)
            let memberId = circle.members.first { $0.initial == initial }?.id
            let player = SessionPlayerModel(
                displayName: name,
                initial: initial,
                buyInCount: count,
                totalIn: totalIn,
                finalOut: finalOut,
                net: net,
                memberId: memberId
            )
            player.session = session
            session.players.append(player)
            context.insert(player)
        }

        let nets = SettlementService.computeNets(players: session.players)
        let payments = SettlementService.minimumPayments(nets: nets)
        for p in payments {
            let model = SettlementPaymentModel(
                fromInitial: p.fromInitial,
                fromName: p.fromName,
                toInitial: p.toInitial,
                toName: p.toName,
                amount: p.amount
            )
            model.session = session
            session.payments.append(model)
            context.insert(model)
        }

        context.insert(session)
        circle.sessions.append(session)
        circle.gameCount += 1
    }
}
