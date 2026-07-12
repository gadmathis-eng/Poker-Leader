import SwiftUI
import SwiftData

struct LiveTableView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    let sessionId: UUID

    @Query private var sessions: [SessionModel]
    @State private var playerMoneyTexts: [UUID: String] = [:]
    @State private var editingMoney: MoneyAmountEditorState?

    private var session: SessionModel? { sessions.first { $0.id == sessionId } }
    private var repo: SessionRepository { SessionRepository(context: context) }

    var body: some View {
        Group {
            if let session {
                VStack(spacing: 0) {
                    VStack(spacing: 8) {
                        SectionHeader(title: "Table mode · live")
                        Text(session.title)
                            .font(.title2.bold())
                            .foregroundStyle(AppTheme.text)
                        Text("POT \(MoneyFormatting.plain(session.potTotal, currencyCode: session.currencyCode))")
                            .font(.title.bold())
                            .foregroundStyle(AppTheme.gold)
                        let totalBuyIns = session.players.reduce(0) { $0 + $1.buyInCount }
                        Text("Tap +/− for standard buy-ins or edit a player's money in directly · \(totalBuyIns) buy-ins")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .padding()

                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(session.players.sorted(by: { $0.displayName < $1.displayName })) { player in
                                HStack {
                                    PlayerAvatarView(initial: player.initial)
                                    VStack(alignment: .leading) {
                                        Text(player.displayName).font(.headline).foregroundStyle(AppTheme.text)
                                        Text("\(player.buyInCount)× buy-in · \(MoneyFormatting.plain(player.totalIn, currencyCode: session.currencyCode))")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.muted)
                                        Button {
                                            editingMoney = MoneyAmountEditorState(
                                                id: player.id,
                                                title: player.displayName,
                                                subtitle: "Money in",
                                                currencyCode: session.currencyCode,
                                                text: decimalText(player.totalIn)
                                            )
                                        } label: {
                                            MoneyAmountPill(label: "Money in", amount: player.totalIn, currencyCode: session.currencyCode)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    Spacer()
                                    HStack(spacing: 12) {
                                        Button {
                                            repo.removeBuyIn(player: player, amount: session.buyInAmount, session: session)
                                            syncMoneyText(for: player)
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .font(.title)
                                                .foregroundStyle(AppTheme.negative)
                                        }
                                        .disabled(player.buyInCount == 0 && player.totalIn == 0)

                                        Button {
                                            repo.addBuyIn(player: player, amount: session.buyInAmount, session: session)
                                            syncMoneyText(for: player)
                                        } label: {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.title)
                                                .foregroundStyle(AppTheme.positive)
                                        }
                                        .disabled(session.buyInAmount <= 0)
                                    }
                                }
                                .padding()
                                .background(AppTheme.card)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                            }
                        }
                        .padding()
                    }

                    Button {
                        router.push(.finalStacks(session.id))
                    } label: {
                        Text("End game · enter results")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(AppTheme.card)
                            .foregroundStyle(AppTheme.text)
                    }
                    .padding()
                }
                .background(AppTheme.background)
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    loadMoneyTexts(for: session)
                }
                .sheet(item: $editingMoney) { editor in
                    MoneyAmountEditorSheet(editor: editor) { text in
                        guard
                            let currentSession = self.session,
                            let player = currentSession.players.first(where: { $0.id == editor.id }),
                            let amount = nonNegativeDecimal(from: text)
                        else { return }

                        repo.updateTotalIn(player: player, amount: amount, session: currentSession)
                        syncMoneyText(for: player)
                    }
                    .presentationDetents([.height(420)])
                    .presentationDragIndicator(.visible)
                }
            } else {
                ContentUnavailableView("Session not found", systemImage: "exclamationmark.circle")
            }
        }
    }

    private func loadMoneyTexts(for session: SessionModel) {
        playerMoneyTexts = Dictionary(uniqueKeysWithValues: session.players.map { ($0.id, decimalText($0.totalIn)) })
    }

    private func syncMoneyText(for player: SessionPlayerModel) {
        playerMoneyTexts[player.id] = decimalText(player.totalIn)
    }

    private func decimalText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value.clampedToNonNegative).stringValue
    }

    private func nonNegativeDecimal(from text: String) -> Decimal? {
        Decimal(string: text.trimmingCharacters(in: .whitespacesAndNewlines))?.clampedToNonNegative
    }

    private func sanitizedNonNegativeDecimalText(_ text: String) -> String {
        if text.contains("-") { return "0" }
        guard let value = Decimal(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return text
        }
        return value < 0 ? "0" : text
    }
}
