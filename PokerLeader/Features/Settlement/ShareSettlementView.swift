import SwiftUI
import SwiftData
import UIKit

struct ShareSettlementView: View {
    let sessionId: UUID
    @Query private var sessions: [SessionModel]

    @State private var didCopySettlement = false
    @State private var didCopyAppLink = false

    private var session: SessionModel? { sessions.first { $0.id == sessionId } }

    var body: some View {
        Group {
            if let session {
                let nets = SettlementService.computeNets(players: session.players)
                let payments = session.payments.map {
                    SettlementPayment(fromName: $0.fromName, fromInitial: $0.fromInitial, toName: $0.toName, toInitial: $0.toInitial, amount: $0.amount)
                }
                let message = WhatsAppMessageBuilder.settlementMessage(session: session, nets: nets, payments: payments)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "Share settlement")
                        Text("Ready to send")
                            .font(.title2.bold())
                            .foregroundStyle(AppTheme.text)

                        SectionHeader(title: "Copy & paste")
                        Text(message)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(AppTheme.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(AppTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))

                        HStack(spacing: 12) {
                            Button {
                                copySettlement(message)
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
                                item: message,
                                subject: Text("\(session.title) · Pot Master"),
                                message: Text(message)
                            ) {
                                HStack(spacing: 10) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Share")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(AppTheme.positive)
                                .foregroundStyle(AppTheme.contrastText)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                            }
                        }

                        SectionHeader(title: "App link")
                        VStack(alignment: .leading, spacing: 12) {
                            Text(SettlementSharing.appLinkMessage(for: session.id))
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(AppTheme.text)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Link(destination: SettlementSharing.appURL(for: session.id)) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.up.forward.app")
                                    Text("Open in Pot Master")
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.positive)
                            }
                        }
                        .padding()
                        .background(AppTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))

                        HStack(spacing: 12) {
                            Button {
                                copyAppLink(for: session.id)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: didCopyAppLink ? "checkmark" : "doc.on.doc")
                                    Text(didCopyAppLink ? "Copied!" : "Copy link")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(didCopyAppLink ? AppTheme.positive.opacity(0.2) : AppTheme.card)
                                .foregroundStyle(didCopyAppLink ? AppTheme.positive : AppTheme.text)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                            }

                            ShareLink(
                                item: SettlementSharing.appURL(for: session.id),
                                subject: Text("Pot Master"),
                                message: Text(SettlementSharing.appLinkMessage(for: session.id))
                            ) {
                                HStack(spacing: 10) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Share link")
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

    private func copySettlement(_ message: String) {
        UIPasteboard.general.string = message
        didCopySettlement = true

        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopySettlement = false
        }
    }

    private func copyAppLink(for sessionId: UUID) {
        UIPasteboard.general.string = SettlementSharing.appLinkMessage(for: sessionId)
        didCopyAppLink = true

        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopyAppLink = false
        }
    }
}
