import Foundation

enum WhatsAppMessageBuilder {
    static func settlementMessage(session: SessionModel, nets: [PlayerNet], payments: [SettlementPayment]) -> String {
        tableSettlementMessage(
            title: session.title,
            currencyCode: session.currencyCode,
            nets: nets,
            payments: payments
        )
    }

    static func tableSettlementMessage(
        title: String,
        currencyCode: String,
        nets: [PlayerNet],
        payments: [SettlementPayment]
    ) -> String {
        var lines = ["♠ \(title) — Who owes who", ""]
        for net in nets {
            lines.append("\(net.name) \(MoneyFormatting.format(net.net, currencyCode: currencyCode))")
        }
        lines.append("")
        if payments.isEmpty {
            lines.append("Nobody owes anybody")
        } else {
            lines.append("Who owes who")
            for payment in payments {
                lines.append(
                    "\(payment.fromName) owes \(payment.toName) \(MoneyFormatting.plain(payment.amount, currencyCode: currencyCode))"
                )
            }
        }
        return lines.joined(separator: "\n")
    }
}
