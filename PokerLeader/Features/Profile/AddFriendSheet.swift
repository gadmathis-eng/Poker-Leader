import SwiftData
import SwiftUI

struct AddFriendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("displayName") private var displayName = "Your name"
    @AppStorage("playerHandle") private var playerHandle = "@yourname"

    @State private var nickname = ""
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var isSending = false

    private var senderHandle: String? {
        MemberModel.normalizedHandle(playerHandle)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nickname")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)

                    TextField("@nickname", text: $nickname)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(16)
                        .background(AppTheme.card)
                        .foregroundStyle(AppTheme.text)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                                .stroke(AppTheme.cardBorder)
                        )
                        .onChange(of: nickname) { _, _ in
                            errorMessage = nil
                            successMessage = nil
                        }
                }

                Text("Send a friend request using their PokerLeader nickname.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(AppTheme.negative)
                }

                if let successMessage {
                    Text(successMessage)
                        .font(.caption)
                        .foregroundStyle(AppTheme.positive)
                }

                Button(action: sendRequest) {
                    Text(isSending ? "Sending..." : "Send request")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canSend ? AppTheme.positive : AppTheme.card)
                        .foregroundStyle(canSend ? AppTheme.contrastText : AppTheme.muted)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                }
                .disabled(!canSend)

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(AppTheme.background)
            .navigationTitle("Add friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppTheme.muted)
                        .disabled(isSending)
                }
            }
        }
    }

    private var canSend: Bool {
        !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private func sendRequest() {
        guard let senderHandle else {
            errorMessage = FriendError.invalidHandle.errorDescription
            return
        }

        isSending = true
        errorMessage = nil
        successMessage = nil

        Task {
            do {
                let repo = FriendRepository(context: context)
                let request = try await repo.sendRequest(
                    targetHandle: nickname,
                    senderHandle: senderHandle,
                    senderDisplayName: displayName
                )
                successMessage = "Request sent to \(request.targetDisplayName ?? request.targetHandle)."
                try? await Task.sleep(for: .milliseconds(900))
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSending = false
            }
        }
    }
}
