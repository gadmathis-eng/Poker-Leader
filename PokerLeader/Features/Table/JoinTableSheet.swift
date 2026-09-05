import SwiftUI
import SwiftData

struct JoinTableSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @AppStorage("displayName") private var displayName = "Your name"
    @AppStorage("playerHandle") private var playerHandle = "@yourname"
    @State private var inviteCode: String
    @State private var errorMessage: String?
    @State private var isJoining = false

    init(initialInviteCode: String? = nil) {
        _inviteCode = State(initialValue: TableInviteDeepLink.normalizedCode(initialInviteCode ?? ""))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Table code") {
                    TextField("Paste table code", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                Section("Joining as") {
                    LabeledContent("Name", value: displayName)
                    if !playerHandle.isEmpty {
                        LabeledContent("Nickname", value: MemberModel.normalizedHandle(playerHandle) ?? playerHandle)
                    }
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(AppTheme.negative)
                    }
                }
                Section {
                    Text("Ask the host for their table link or code. You'll pick a seat once you're at the table.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Join a table")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isJoining ? "Joining..." : "Join") { join() }
                        .disabled(normalizedInviteCode.isEmpty || isJoining)
                }
            }
        }
    }

    private var normalizedInviteCode: String {
        TableInviteDeepLink.normalizedCode(inviteCode)
    }

    private func join() {
        isJoining = true
        errorMessage = nil
        let code = normalizedInviteCode

        Task {
            do {
                let repo = TableRepository(context: context)
                let table = try await repo.join(inviteCode: code, displayName: displayName)
                router.pendingTableInviteCode = table.inviteCode
                dismiss()
            } catch let error as TableRepositoryError where error == .notSignedIn {
                router.pendingTableInviteCode = code
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isJoining = false
            }
        }
    }
}
