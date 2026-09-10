import SwiftUI
import UIKit

/// Who owes who once the table is cashed out: each player's stack against what
/// they put in, then the fewest payments that settle it.
struct TableSettlementSheet: View {
    let title: String
    let currencyCode: String
    let seats: [SharedTableSeat]
    let hand: SharedTableHand?

    @Environment(\.dismiss) private var dismiss
    @State private var didCopy = false

    private var nets: [PlayerNet] {
        SettlementService.computeNets(seats: seats, hand: hand)
    }

    private var payments: [SettlementPayment] {
        SettlementService.minimumPayments(nets: nets)
    }

    private var isHandInPlay: Bool {
        guard let hand else { return false }
        return !hand.isComplete
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(title: "End game")
                        Text("Who owes who")
                            .font(.title2.bold())
                            .foregroundStyle(AppTheme.text)
                        Text(title)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.muted)
                    }

                    if isHandInPlay {
                        Text("The hand in play is paused. Bets go back to whoever put them in.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }

                    if seats.isEmpty {
                        Text("Nobody is sitting yet.")
                            .font(.body)
                            .foregroundStyle(AppTheme.muted)
                    } else if payments.isEmpty {
                        Text("Nobody owes anybody. Everyone is even.")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppTheme.text)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                    } else {
                        SectionHeader(title: "Who owes who")
                        ForEach(payments) { payment in
                            HStack {
                                Text("\(payment.fromName) owes \(payment.toName)")
                                Spacer()
                                PlayerAvatarView(initial: payment.toInitial, size: 28)
                                MoneyText(
                                    amount: payment.amount,
                                    currencyCode: currencyCode,
                                    showSign: false
                                )
                            }
                            .foregroundStyle(AppTheme.text)
                            .padding()
                            .background(AppTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        }
                    }

                    if !nets.isEmpty {
                        SectionHeader(title: "Net results")
                        ForEach(Array(nets.enumerated()), id: \.element.id) { index, net in
                            HStack {
                                Text("\(index + 1)")
                                PlayerAvatarView(initial: net.initial, size: 32)
                                Text(net.name)
                                Spacer()
                                MoneyText(amount: net.net, currencyCode: currencyCode)
                            }
                            .foregroundStyle(AppTheme.text)
                            .padding()
                            .background(AppTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        }
                    }

                    if !seats.isEmpty {
                        SectionHeader(title: "Copy & paste")
                        Text(settlementMessage)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(AppTheme.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(AppTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))

                        HStack(spacing: 12) {
                            Button(action: copySettlement) {
                                HStack(spacing: 10) {
                                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                                    Text(didCopy ? "Copied!" : "Copy")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(didCopy ? AppTheme.positive.opacity(0.2) : AppTheme.card)
                                .foregroundStyle(didCopy ? AppTheme.positive : AppTheme.text)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                            }

                            ShareLink(
                                item: settlementMessage,
                                subject: Text("\(title) · Pot Master"),
                                message: Text(settlementMessage)
                            ) {
                                HStack(spacing: 10) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Share")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(AppTheme.card)
                                .foregroundStyle(AppTheme.text)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                            }
                        }
                    }
                }
                .padding()
            }
            .background(AppTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var settlementMessage: String {
        WhatsAppMessageBuilder.tableSettlementMessage(
            title: title,
            currencyCode: currencyCode,
            nets: nets,
            payments: payments
        )
    }

    private func copySettlement() {
        UIPasteboard.general.string = settlementMessage
        didCopy = true

        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }
}
