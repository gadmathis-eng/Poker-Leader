import SwiftUI

/// Says out loud that none of this money is real. It appears on every screen
/// where a figure is shown, because a player should never have to work out
/// which mode they are in.
struct DemoFundsBadge: View {
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "testtube.2")
                .font(.caption2.weight(.bold))
            Text(compact ? "Demo Funds" : "Test Mode · Demo Funds")
                .font(.caption2.weight(.bold))
                .tracking(0.6)
        }
        .foregroundStyle(AppTheme.gold)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(AppTheme.gold.opacity(0.14))
        .clipShape(Capsule())
        .accessibilityLabel("Test mode. This is demo money, not real money.")
    }
}

struct VaultNoticeCard: View {
    let title: String
    let message: String
    var tint: Color = AppTheme.text
    var iconName: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let iconName {
                Image(systemName: iconName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// One figure with its label. `isPrimary` is the total, which is set larger.
struct VaultBalanceTile: View {
    let title: String
    let amount: Money
    let currencyCode: String
    var tint: Color = AppTheme.text
    var isPrimary = false
    var footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(AppTheme.muted)

            Text(amount.formatted(currencyCode: currencyCode))
                .font(isPrimary
                    ? .system(size: 34, weight: .heavy, design: .rounded)
                    : .title3.weight(.bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(tint)
                .monospacedDigit()

            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: isPrimary ? 108 : 84, alignment: .leading)
        .cardSurface(padding: 16, cornerRadius: 20)
    }
}

struct VaultPrimaryButton: View {
    let title: String
    var systemImage: String?
    var tint: Color = AppTheme.positive
    var isEnabled = true
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AppTheme.contrastText)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.bold))
                }
                Text(title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isEnabled && !isBusy ? tint : AppTheme.card)
            .foregroundStyle(isEnabled && !isBusy ? AppTheme.contrastText : AppTheme.muted)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isBusy)
    }
}

struct VaultSecondaryButton: View {
    let title: String
    var systemImage: String?
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.bold))
                }
                Text(title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(AppTheme.card)
            .foregroundStyle(isEnabled ? AppTheme.text : AppTheme.muted)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(AppTheme.cardBorder)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

/// A row of round-number shortcuts above the keypad.
struct SuggestedAmountRow: View {
    let amounts: [Money]
    let currencyCode: String
    @Binding var selection: Money?
    let onSelect: (Money) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(amounts, id: \.cents) { amount in
                Button {
                    selection = amount
                    onSelect(amount)
                } label: {
                    Text(amount.formatted(currencyCode: currencyCode))
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(selection == amount ? AppTheme.positive : AppTheme.card)
                        .foregroundStyle(selection == amount ? AppTheme.contrastText : AppTheme.text)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                                .stroke(AppTheme.cardBorder)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct VaultTransactionRow: View {
    let transaction: VaultTransaction

    private var statusTint: Color {
        if transaction.status.isUnhappy { return AppTheme.negative }
        if transaction.status == .pending { return AppTheme.gold }
        if transaction.status == .canceled { return AppTheme.muted }
        return AppTheme.positive
    }

    private var amountTint: Color {
        transaction.amount.isNegative ? AppTheme.negative : AppTheme.positive
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: transaction.kind.iconName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(statusTint)
                .frame(width: 34, height: 34)
                .background(statusTint.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.kind.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.text)

                Text(VaultDateFormatting.dateAndTime(transaction.createdAt))
                    .font(.caption2)
                    .foregroundStyle(AppTheme.muted)

                if let detail = transaction.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    Text(transaction.referenceCode)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(AppTheme.muted)
                        .textSelection(.enabled)

                    if let code = transaction.tableInviteCode {
                        Text("· Table \(code)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(AppTheme.muted)
                    }
                }

                if transaction.isDemo {
                    DemoFundsBadge(compact: true)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                if transaction.showsAmount {
                    Text(transaction.amount.formattedSigned(currencyCode: transaction.currencyCode))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(amountTint)
                        .monospacedDigit()
                } else {
                    // Money that only moved between the player's own buckets. The
                    // total they own did not change, so there is no figure to add
                    // or subtract here.
                    Text("Moved")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                }

                Text(transaction.status.label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(statusTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusTint.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 10)
    }
}

enum VaultDateFormatting {
    static func dateAndTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
