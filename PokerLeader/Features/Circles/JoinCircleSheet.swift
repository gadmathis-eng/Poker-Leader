import SwiftUI
import SwiftData

struct JoinCircleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("displayName") private var displayName = "Your name"
    @AppStorage("playerHandle") private var playerHandle = "@yourname"
    @State private var inviteCode: String
    @State private var errorMessage: String?
    @State private var isJoining = false

    init(initialInviteCode: String? = nil) {
        _inviteCode = State(initialValue: initialInviteCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Creator invite code") {
                    TextField("Paste invite code", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
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
                    Text("You can only join a circle with an invite code sent by that circle's creator.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Join with invite")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isJoining ? "Joining..." : "Join") { join() }
                        .disabled(inviteCode.trimmingCharacters(in: .whitespaces).isEmpty || isJoining)
                }
            }
        }
    }

    private func join() {
        isJoining = true
        errorMessage = nil
        Task {
            do {
                let repo = CircleRepository(context: context)
                if let _ = try await repo.joinWithInviteCode(
                    inviteCode,
                    displayName: displayName,
                    initial: CircleRepository.initial(for: displayName),
                    handle: playerHandle
                ) {
                    dismiss()
                } else {
                    errorMessage = "No circle found for that code."
                    isJoining = false
                }
            } catch {
                errorMessage = error.localizedDescription
                isJoining = false
            }
        }
    }
}
