import SwiftUI

struct CreateTableButton: View {
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(isBusy ? "Creating..." : "Create table", systemImage: "plus.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(AppTheme.positive)
                .foregroundStyle(AppTheme.contrastText)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel("Create table")
        .accessibilityHint("Starts a new hosted poker table")
    }
}
