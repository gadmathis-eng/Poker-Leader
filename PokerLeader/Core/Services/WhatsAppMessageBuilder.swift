import Foundation

enum WhatsAppMessageBuilder {
    static func settlementMessage(session: SessionModel, nets: [PlayerNet], payments: [SettlementPayment]) -> String {
        var lines = ["♠ \(session.title) — Settlement", ""]
        for net in nets {
            lines.append("\(net.name) \(MoneyFormatting.format(net.net, currencyCode: session.currencyCode))")
        }
        lines.append("")
        lines.append("Payments")
        for payment in payments {
            lines.append("\(payment.fromName) → \(payment.toName) \(MoneyFormatting.plain(payment.amount, currencyCode: session.currencyCode))")
        }
        return lines.joined(separator: "\n")
    }
}
