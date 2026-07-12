import SwiftUI
import SwiftData
import UIKit

struct SettlementResultsView: View {
    let sessionId: UUID
    @Query private var sessions: [SessionModel]
    @State private var didCopySettlement = false

    private var session: SessionModel? { sessions.first { $0.id == sessionId } }

    var body: some View {
        Group {
            if let session {
                let nets = SettlementService.computeNets(players: session.players)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        SectionHeader(title: "Results & settlement")
                        Text("Settle the damage")
                            .font(.title2.bold())
                            .foregroundStyle(AppTheme.text)

                        SectionHeader(title: "Net results")
                        ForEach(Array(nets.enumerated()), id: \.element.id) { index, net in
                            HStack {
                                Text("\(index + 1)")
                                PlayerAvatarView(initial: net.initial, size: 32)
                                Text(net.name)
                                Spacer()
                                MoneyText(amount: net.net, currencyCode: session.currencyCode)
                            }
                            .foregroundStyle(AppTheme.text)
                            .padding()
                            .background(AppTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        }

                        SectionHeader(title: "Settlements")

                        ForEach(session.payments) { payment in
                            HStack {
                                Text("\(payment.fromName) pays \(payment.toName)")
                                Spacer()
                                PlayerAvatarView(initial: payment.toInitial, size: 28)
                                MoneyText(amount: payment.amount, currencyCode: session.currencyCode, showSign: false)
                            }
                            .foregroundStyle(AppTheme.text)
                            .padding()
                            .background(AppTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        }

                        SectionHeader(title: "Copy & paste")
                        Text(settlementMessage(for: session))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(AppTheme.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(AppTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))

                        HStack(spacing: 12) {
                            Button {
                                copySettlement(for: session)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: didCopySettlement ? "checkmark" : "doc.on.doc")
                                    Text(didCopySettlement ? "Copied!" : "Copy")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(didCopySettlement ? AppTheme.positive.opacity(0.2) : AppTheme.card)
                                .foregroundStyle(didCopySettlement ? AppTheme.positive : AppTheme.text)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                            }

                            ShareLink(
                                item: settlementMessage(for: session),
                                subject: Text("\(session.title) · Pot Master"),
                                message: Text(settlementMessage(for: session))
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
                    .padding()
                }
                .background(AppTheme.background)
            } else {
                ContentUnavailableView("Session not found", systemImage: "exclamationmark.circle")
            }
        }
    }

    private func settlementMessage(for session: SessionModel) -> String {
        let nets = SettlementService.computeNets(players: session.players)
        let payments = settlementPayments(for: session)
        return WhatsAppMessageBuilder.settlementMessage(session: session, nets: nets, payments: payments)
    }

    private func settlementPayments(for session: SessionModel) -> [SettlementPayment] {
        session.payments.map {
            SettlementPayment(
                fromName: $0.fromName,
                fromInitial: $0.fromInitial,
                toName: $0.toName,
                toInitial: $0.toInitial,
                amount: $0.amount
            )
        }
    }

    private func copySettlement(for session: SessionModel) {
        UIPasteboard.general.string = settlementMessage(for: session)
        didCopySettlement = true

        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopySettlement = false
        }
    }
}
