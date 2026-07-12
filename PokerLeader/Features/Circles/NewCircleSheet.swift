import SwiftUI
import SwiftData

struct NewCircleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("displayName") private var displayName = "Your name"
    @AppStorage("playerHandle") private var playerHandle = "@yourname"
    @State private var name = ""
    @State private var currencyCode: String
    @State private var showingCurrencyPicker = false
    @State private var isCreating = false
    @State private var errorMessage: String?

    init() {
        _currencyCode = State(initialValue: UserDefaults.standard.string(forKey: "preferredCurrencyCode") ?? CurrencyPreferences.defaultCurrencyCode)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 0) {
                    TextField("Circle nickname", text: $name)
                        .textInputAutocapitalization(.words)
                        .padding()
                        .foregroundStyle(AppTheme.text)

                    Divider().overlay(AppTheme.cardBorder)

                    HStack {
                        Text("Currency")
                            .foregroundStyle(AppTheme.text)
                        Spacer()
                        CurrencyChipButton(currencyCode: currencyCode) {
                            showingCurrencyPicker = true
                        }
                    }
                    .padding()
                }
                .background(AppTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))

                Text("A unique invite code is created automatically, so circles with similar nicknames never overlap.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(AppTheme.negative)
                }

                Spacer()
            }
            .padding()
            .background(AppTheme.background)
            .navigationTitle("New circle")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isCreating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreating ? "Creating..." : "Create") { createCircle() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !CurrencyPreferences.isValidCurrencyCode(currencyCode) || isCreating)
                }
            }
            .sheet(isPresented: $showingCurrencyPicker) {
                CurrencyPickerSheet(selectedCurrencyCode: currencyCode) { code in
                    currencyCode = CurrencyPreferences.normalizedCurrencyCode(code)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private func createCircle() {
        isCreating = true
        errorMessage = nil
        Task {
            do {
                let repo = CircleRepository(context: context)
                let circle = try await repo.createSynced(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    currentUserDisplayName: displayName,
                    currentUserHandle: playerHandle,
                    currencyCode: CurrencyPreferences.normalizedCurrencyCode(currencyCode)
                )
                CircleCreatorStore.markCreator(circle.id)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }
}
