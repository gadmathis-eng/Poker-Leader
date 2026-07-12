import SwiftUI
import SwiftData

struct ConfirmationView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    let sessionId: UUID

    @Query private var sessions: [SessionModel]
    private var session: SessionModel? { sessions.first { $0.id == sessionId } }
    private var repo: SessionRepository { SessionRepository(context: context) }

    var body: some View {
        Group {
            if let session {
                let check = SettlementService.potIsBalanced(players: session.players)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "Confirmation")
                        Text("Check the numbers")
                            .font(.title2.bold())
                            .foregroundStyle(AppTheme.text)

                        VStack(spacing: 0) {
                            HStack {
                                Text("PLAYER").frame(maxWidth: .infinity, alignment: .leading)
                                Text("IN").frame(width: 70)
                                Text("OUT").frame(width: 70)
                            }
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.muted)
                            .padding(.bottom, 8)

                            ForEach(session.players) { player in
                                HStack {
                                    Text(player.displayName).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(MoneyFormatting.plain(player.totalIn, currencyCode: session.currencyCode)).frame(width: 70)
                                    Text(MoneyFormatting.plain(player.finalOut ?? 0, currencyCode: session.currencyCode)).frame(width: 70)
                                }
                                .foregroundStyle(AppTheme.text)
                                .padding(.vertical, 8)
                            }
                        }
                        .padding()
                        .background(AppTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))

                        if check.balanced {
                            Text("The maths checks out")
                                .font(.headline)
                                .foregroundStyle(AppTheme.positive)
                            Text("\(MoneyFormatting.plain(check.totalIn, currencyCode: session.currencyCode)) in · \(MoneyFormatting.plain(check.totalOut, currencyCode: session.currencyCode)) out · nothing missing")
                                .font(.caption)
                                .foregroundStyle(AppTheme.muted)
                            Button {
                                repo.settle(session: session)
                                router.push(.settlement(session.id))
                            } label: {
                                Text("Confirm & settle")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(AppTheme.positive)
                                    .foregroundStyle(AppTheme.contrastText)
                                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                            }
                        } else {
                            Text("Something's off")
                                .font(.headline)
                                .foregroundStyle(AppTheme.negative)
                            Text("The table is missing \(MoneyFormatting.plain(SettlementService.missingAmount(players: session.players), currencyCode: session.currencyCode)). Check before you settle.")
                                .font(.caption)
                                .foregroundStyle(AppTheme.muted)
                            Button { if !router.circlesPath.isEmpty { router.circlesPath.removeLast() } } label: {
                                Text("Recount stacks")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(AppTheme.negative.opacity(0.2))
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
}
