import SwiftUI
import SwiftData

struct FinalStacksView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    let sessionId: UUID

    @Query private var sessions: [SessionModel]
    @State private var stackTexts: [UUID: String] = [:]
    @State private var editingStack: MoneyAmountEditorState?

    private var session: SessionModel? { sessions.first { $0.id == sessionId } }
    private var repo: SessionRepository { SessionRepository(context: context) }

    var body: some View {
        Group {
            if let session {
                let check = livePotCheck(for: session)
                let canReview = canReview(session: session, check: check)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 10) {
                            Image(systemName: "sum")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(AppTheme.gold)
                                .frame(width: 36, height: 36)
                                .background(AppTheme.card)
                                .clipShape(Circle())
                            SectionHeader(title: "Final stacks")
                        }
                        Text("Enter what each player walked away with.")
                            .foregroundStyle(AppTheme.muted)

                        ForEach(session.players) { player in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(player.displayName)
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.text)
                                HStack {
                                    Text("in \(MoneyFormatting.plain(player.totalIn, currencyCode: session.currencyCode))")
                                        .foregroundStyle(AppTheme.muted)
                                    Spacer()
                                    Button {
                                        editingStack = MoneyAmountEditorState(
                                            id: player.id,
                                            title: player.displayName,
                                            subtitle: "Final stack",
                                            currencyCode: session.currencyCode,
                                            text: stackTexts[player.id] ?? player.finalOut.map(decimalText) ?? "0"
                                        )
                                    } label: {
                                        MoneyAmountPill(
                                            label: "Final stack",
                                            amount: nonNegativeDecimal(from: stackTexts[player.id] ?? "") ?? player.finalOut ?? 0,
                                            currencyCode: session.currencyCode
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding()
                            .background(AppTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                            .onAppear {
                                if stackTexts[player.id] == nil, let out = player.finalOut {
                                    stackTexts[player.id] = decimalText(out)
                                }
                            }
                        }

                        PotCheckBanner(
                            balanced: check.balanced,
                            totalIn: check.totalIn,
                            totalOut: check.totalOut,
                            currencyCode: session.currencyCode
                        )

                        Button {
                            if saveStacks(session: session) {
                                router.push(.confirmation(session.id))
                            }
                        } label: {
                            Text("Review settlement →")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(canReview ? AppTheme.positive : AppTheme.card)
                                .foregroundStyle(canReview ? AppTheme.contrastText : AppTheme.text)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        }
                        .disabled(!canReview)
                    }
                    .padding()
                }
                .background(AppTheme.background)
                .navigationTitle("Final stacks")
                .sheet(item: $editingStack) { editor in
                    MoneyAmountEditorSheet(editor: editor) { text in
                        stackTexts[editor.id] = sanitizedNonNegativeDecimalText(text)
                    }
                    .presentationDetents([.height(420)])
                    .presentationDragIndicator(.visible)
                }
            } else {
                ContentUnavailableView("Session not found", systemImage: "exclamationmark.circle")
            }
        }
    }

    private func livePotCheck(for session: SessionModel) -> (balanced: Bool, totalIn: Decimal, totalOut: Decimal) {
        let totalIn = session.players.reduce(0) { $0 + $1.totalIn }
        let totalOut = session.players.reduce(Decimal(0)) { total, player in
            total + finalStackAmount(for: player)
        }
        return (totalIn == totalOut, totalIn, totalOut)
    }

    private func finalStackAmount(for player: SessionPlayerModel) -> Decimal {
        if let text = stackTexts[player.id], let amount = nonNegativeDecimal(from: text) {
            return amount
        }
        return player.finalOut ?? 0
    }

    private func saveStacks(session: SessionModel) -> Bool {
        guard enteredStacksAreValid(session: session) else { return false }

        for player in session.players {
            repo.updateFinalOut(player: player, amount: finalStackAmount(for: player))
        }
        return true
    }

    private func enteredStacksAreValid(session: SessionModel) -> Bool {
        session.players.allSatisfy { player in
            guard let text = stackTexts[player.id], !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return true
            }
            return nonNegativeDecimal(from: text) != nil
        }
    }

    private func canReview(
        session: SessionModel,
        check: (balanced: Bool, totalIn: Decimal, totalOut: Decimal)
    ) -> Bool {
        enteredStacksAreValid(session: session) && check.balanced
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

    private func decimalText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value.clampedToNonNegative).stringValue
    }
}
