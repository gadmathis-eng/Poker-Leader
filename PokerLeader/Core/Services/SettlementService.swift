import Foundation

struct SettlementPayment: Identifiable, Equatable {
    let id = UUID()
    let fromName: String
    let fromInitial: String
    let toName: String
    let toInitial: String
    let amount: Decimal
}

struct PlayerNet: Identifiable {
    let id: UUID
    let name: String
    let initial: String
    let net: Decimal
}

enum SettlementService {
    static func computeNets(players: [SessionPlayerModel]) -> [PlayerNet] {
        players.map { player in
            let out = player.finalOut ?? 0
            let net = out - player.totalIn
            return PlayerNet(id: player.id, name: player.displayName, initial: player.initial, net: net)
        }
        .sorted { $0.net > $1.net }
    }

    static func potIsBalanced(players: [SessionPlayerModel]) -> (balanced: Bool, totalIn: Decimal, totalOut: Decimal) {
        let totalIn = players.reduce(0) { $0 + $1.totalIn }
        let totalOut = players.reduce(0) { $0 + ($1.finalOut ?? 0) }
        return (totalIn == totalOut, totalIn, totalOut)
    }

    static func missingAmount(players: [SessionPlayerModel]) -> Decimal {
        let check = potIsBalanced(players: players)
        return abs(check.totalIn - check.totalOut)
    }

    static func minimumPayments(nets: [PlayerNet]) -> [SettlementPayment] {
        var creditors: [(String, String, Decimal)] = []
        var debtors: [(String, String, Decimal)] = []

        for net in nets {
            if net.net > 0 {
                creditors.append((net.name, net.initial, net.net))
            } else if net.net < 0 {
                debtors.append((net.name, net.initial, abs(net.net)))
            }
        }

        creditors.sort { $0.2 > $1.2 }
        debtors.sort { $0.2 > $1.2 }

        var payments: [SettlementPayment] = []
        var ci = 0
        var di = 0

        while ci < creditors.count && di < debtors.count {
            let pay = min(creditors[ci].2, debtors[di].2)
            if pay > 0 {
                payments.append(SettlementPayment(
                    fromName: debtors[di].0,
                    fromInitial: debtors[di].1,
                    toName: creditors[ci].0,
                    toInitial: creditors[ci].1,
                    amount: pay
                ))
            }
            var creditor = creditors[ci]
            creditor.2 -= pay
            creditors[ci] = creditor
            var debtor = debtors[di]
            debtor.2 -= pay
            debtors[di] = debtor
            if creditors[ci].2 == 0 { ci += 1 }
            if debtors[di].2 == 0 { di += 1 }
        }

        return payments
    }
}
