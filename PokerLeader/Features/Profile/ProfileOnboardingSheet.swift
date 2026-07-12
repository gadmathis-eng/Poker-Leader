import SwiftData
import SwiftUI

struct ProfileOnboardingSheet: View {
    @Environment(\.modelContext) private var context
    @Query private var circles: [CircleModel]

    @Binding var displayName: String
    @Binding var playerHandle: String

    @State private var draftDisplayName: String
    @State private var suggestedNickname = "@player"
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(displayName: Binding<String>, playerHandle: Binding<String>) {
        self._displayName = displayName
        self._playerHandle = playerHandle

        let initialName = displayName.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        self._draftDisplayName = State(initialValue: MemberModel.isPlaceholderName(initialName) ? "" : initialName)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Create your poker profile")
                        .font(.title2.bold())
                        .foregroundStyle(AppTheme.text)

                    Text("Choose a real name. Real names and nicknames must be unique across Pot Master.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }

                VStack(alignment: .leading, spacing: 10) {
                    TextField("Real name", text: $draftDisplayName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .background(AppTheme.card)
                        .foregroundStyle(AppTheme.text)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(AppTheme.negative)
                    }

                    Text(suggestedNickname)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(AppTheme.card)
                        .foregroundStyle(AppTheme.text)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                }

                Spacer()
            }
            .padding()
            .background(AppTheme.background)
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        Task { await saveProfile() }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.positive)
                    .disabled(isSaving || draftDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || errorMessage != nil)
                }
            }
            .task(id: draftDisplayName) {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                refreshSuggestedNickname()
                validateDisplayName()
            }
        }
        .interactiveDismissDisabled()
    }

    private func validateDisplayName() {
        let cleanedDisplayName = draftDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedDisplayName.isEmpty, !MemberModel.isPlaceholderName(cleanedDisplayName) else {
            errorMessage = nil
            return
        }

        if DisplayNameService.localReservedDisplayNames(in: context).contains(cleanedDisplayName.lowercased()) {
            errorMessage = SupabaseSyncError.displayNameTaken(cleanedDisplayName).errorDescription
            return
        }

        errorMessage = nil
    }

    private func refreshSuggestedNickname() {
        let cleanedDisplayName = draftDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedDisplayName.isEmpty, !MemberModel.isPlaceholderName(cleanedDisplayName) else {
            suggestedNickname = "@player"
            return
        }

        suggestedNickname = NicknameService.generateAvailableLocally(
            for: cleanedDisplayName,
            in: context
        )
    }

    private func saveProfile() async {
        let cleanedDisplayName = draftDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedDisplayName.isEmpty, !MemberModel.isPlaceholderName(cleanedDisplayName) else {
            errorMessage = "Choose your real name first."
            return
        }

        guard errorMessage == nil else { return }

        isSaving = true
        defer { isSaving = false }

        let cleanedHandle = suggestedNickname

        displayName = cleanedDisplayName
        playerHandle = cleanedHandle

        for member in circles.flatMap(\.members).filter(\.isCurrentUser) {
            member.displayName = cleanedDisplayName
            member.initial = CircleRepository.initial(for: cleanedDisplayName)
            member.handle = cleanedHandle

            if let circle = member.circle {
                for session in circle.sessions {
                    for player in session.players where player.memberId == member.id {
                        player.displayName = member.displayName(preferredHandle: cleanedHandle)
                        player.initial = member.initial
                    }
                }
            }
        }

        try? context.save()

        Task {
            try? await DisplayNameService.validateAvailable(cleanedDisplayName, in: context)
            try? await NicknameService.validateAvailable(cleanedHandle, in: context)
            if SupabaseAuthManager.shared.isSignedIn {
                try? await SupabaseSyncService.shared.upsertUserProfile(
                    handle: cleanedHandle,
                    displayName: cleanedDisplayName
                )
            }
        }
    }
}
