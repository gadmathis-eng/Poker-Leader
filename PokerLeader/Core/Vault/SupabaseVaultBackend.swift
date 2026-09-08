import Foundation
import Supabase

/// Talks to the Vault functions in Postgres.
///
/// Every call is an RPC rather than a table write. The tables themselves grant
/// `select` and nothing else to a signed-in player, and row-level security
/// narrows even that to their own rows, so this type could not write a balance
/// if it tried. Authorisation is decided inside each function, against
/// `auth.uid()`, from the JWT — not from anything sent here.
@MainActor
struct SupabaseVaultBackend: VaultBackend {
    var isAvailable: Bool {
        SupabaseBootstrap.isConfigured && SupabaseAuthManager.shared.isSignedIn
    }

    private func client() throws -> SupabaseClient {
        guard SupabaseAuthManager.shared.isSignedIn else { throw VaultError.notSignedIn }
        do {
            return try SupabaseBootstrap.requireClient()
        } catch {
            throw VaultError.notAvailable
        }
    }

    private func call<Params: Encodable, Result: Decodable>(
        _ function: String,
        params: Params,
        as: Result.Type = Result.self
    ) async throws -> Result {
        do {
            return try await client().rpc(function, params: params).execute().value
        } catch {
            throw VaultError.from(error)
        }
    }

    private func call<Result: Decodable>(
        _ function: String,
        as: Result.Type = Result.self
    ) async throws -> Result {
        do {
            return try await client().rpc(function).execute().value
        } catch {
            throw VaultError.from(error)
        }
    }

    // MARK: - Reading

    func openVault() async throws -> VaultSummary {
        try await call(
            "vault_open",
            params: CurrencyParams(p_currency: VaultFX.preferredOpeningCurrency()),
            as: SummaryRow.self
        )
        .model
    }

    func summary() async throws -> VaultSummary {
        try await call("vault_summary", as: SummaryRow.self).model
    }

    func transactions(limit: Int) async throws -> [VaultTransaction] {
        let rows: [StatementRow] = try await call(
            "vault_statement",
            params: StatementParams(p_limit: limit, p_before: nil)
        )
        return rows.compactMap(\.model)
    }

    // MARK: - Deposits

    func createDepositIntent(
        amount: Money,
        purpose: DepositPurpose,
        tableInviteCode: String?,
        currencyCode: String,
        idempotencyKey: String
    ) async throws -> DepositIntent {
        let row: IntentRow = try await call(
            "vault_create_deposit_intent",
            params: CreateIntentParams(
                p_amount_cents: amount.cents,
                p_idempotency_key: idempotencyKey,
                p_purpose: purpose.rawValue,
                p_table_invite_code: tableInviteCode,
                p_provider: VaultProviders.payment.backendProviderName,
                p_currency: VaultFX.normalize(currencyCode)
            )
        )
        return row.model
    }

    func confirmDeposit(intentID: UUID) async throws -> DepositIntent {
        let row: IntentRow = try await call(
            "vault_sandbox_confirm_deposit",
            params: ConfirmDepositParams(p_intent_id: intentID)
        )
        return row.model
    }

    func cancelDeposit(intentID: UUID) async throws -> DepositIntent {
        let row: IntentRow = try await call(
            "vault_cancel_deposit_intent",
            params: ConfirmDepositParams(p_intent_id: intentID)
        )
        return row.model
    }

    // MARK: - Tables

    func registerTable(
        inviteCode: String,
        minimum: Money,
        maximum: Money,
        currencyCode: String
    ) async throws -> TableBuyInLimits {
        let row: TableRow = try await call(
            "vault_register_table",
            params: RegisterTableParams(
                p_invite_code: inviteCode,
                p_min_buy_in_cents: minimum.cents,
                p_max_buy_in_cents: maximum.cents,
                p_currency: currencyCode
            )
        )
        return row.model
    }

    func tableLimits(inviteCode: String) async throws -> TableBuyInLimits? {
        do {
            let rows: [TableRow] = try await client()
                .from("vault_tables")
                .select()
                .eq("invite_code", value: inviteCode.uppercased())
                .limit(1)
                .execute()
                .value
            return rows.first?.model
        } catch {
            throw VaultError.from(error)
        }
    }

    func buyIn(
        inviteCode: String,
        amount: Money,
        source: TableBuyInSource,
        playerKey: String,
        displayName: String,
        paymentIntentID: UUID?,
        idempotencyKey: String
    ) async throws -> TableBuyInReceipt {
        // Identity is auth.uid() on the server. playerKey is kept on the
        // protocol so the in-app sandbox can still match local seats.
        _ = playerKey
        let row: BuyInRow = try await call(
            "vault_table_buy_in",
            params: BuyInParams(
                p_invite_code: inviteCode,
                p_amount_cents: amount.cents,
                p_source: source.rawValue,
                p_idempotency_key: idempotencyKey,
                p_display_name: displayName,
                p_payment_intent_id: paymentIntentID
            )
        )
        return row.model
    }

    func tableChips(inviteCode: String) async throws -> [TableChipCount] {
        let rows: [ChipRow] = try await call(
            "vault_table_chips",
            params: InviteCodeParams(p_invite_code: inviteCode)
        )
        return rows.map(\.model)
    }

    func recordHand(inviteCode: String, handID: String, deltas: [String: Money]) async throws {
        _ = inviteCode
        _ = handID
        _ = deltas
        throw VaultError.backend("The server records the hand. Send a betting action, not a result.")
    }

    func startHand(inviteCode: String) async throws -> SharedTableHand {
        try await call(
            "poker_start_hand",
            params: InviteCodeParams(p_invite_code: inviteCode),
            as: SharedTableHand.self
        )
    }

    func act(
        inviteCode: String,
        action: HandMove,
        amount: Money?,
        actionID: String
    ) async throws -> SharedTableHand {
        try await call(
            "poker_act",
            params: PokerActParams(
                p_invite_code: inviteCode,
                p_action: action.rawValue,
                p_amount_cents: amount?.cents,
                p_action_id: actionID
            ),
            as: SharedTableHand.self
        )
    }

    func handView(inviteCode: String) async throws -> SharedTableHand? {
        try await call(
            "poker_hand_view",
            params: InviteCodeParams(p_invite_code: inviteCode),
            as: SharedTableHand?.self
        )
    }

    func leaveTable(inviteCode: String, idempotencyKey: String) async throws -> TableSettlement {
        let row: SettlementRow = try await call(
            "vault_leave_table",
            params: LeaveTableParams(
                p_invite_code: inviteCode,
                p_idempotency_key: idempotencyKey
            )
        )
        return row.model
    }

    // MARK: - Withdrawals

    func requestWithdrawal(
        amount: Money,
        currencyCode: String,
        idempotencyKey: String
    ) async throws -> WithdrawalRequest {
        let row: WithdrawalRow = try await call(
            "vault_request_withdrawal",
            params: WithdrawalParams(
                p_amount_cents: amount.cents,
                p_idempotency_key: idempotencyKey,
                p_currency: CurrencyPreferences.normalizedCurrencyCode(currencyCode)
            )
        )
        return row.model
    }

    func withdrawals() async throws -> [WithdrawalRequest] {
        do {
            let rows: [WithdrawalRow] = try await client()
                .from("vault_withdrawals")
                .select()
                .order("requested_at", ascending: false)
                .limit(50)
                .execute()
                .value
            return rows.map(\.model)
        } catch {
            throw VaultError.from(error)
        }
    }

    func cancelWithdrawal(id: UUID) async throws -> WithdrawalRequest {
        let row: WithdrawalRow = try await call(
            "vault_cancel_withdrawal",
            params: WithdrawalIDParams(p_withdrawal_id: id)
        )
        return row.model
    }

    func settleWithdrawalInSandbox(id: UUID, succeeds: Bool) async throws -> WithdrawalRequest {
        let row: WithdrawalRow = try await call(
            "vault_sandbox_resolve_withdrawal",
            params: ResolveWithdrawalParams(
                p_withdrawal_id: id,
                p_outcome: succeeds ? "completed" : "failed"
            )
        )
        return row.model
    }
}

// MARK: - Function parameters

private struct CurrencyParams: Encodable { let p_currency: String }
private struct StatementParams: Encodable { let p_limit: Int; let p_before: Date? }
private struct InviteCodeParams: Encodable { let p_invite_code: String }
private struct WithdrawalIDParams: Encodable { let p_withdrawal_id: UUID }

private struct CreateIntentParams: Encodable {
    let p_amount_cents: Int
    let p_idempotency_key: String
    let p_purpose: String
    let p_table_invite_code: String?
    let p_provider: String
    let p_currency: String
}

private struct ConfirmDepositParams: Encodable {
    let p_intent_id: UUID
}

private struct RegisterTableParams: Encodable {
    let p_invite_code: String
    let p_min_buy_in_cents: Int
    let p_max_buy_in_cents: Int
    let p_currency: String
}

private struct BuyInParams: Encodable {
    let p_invite_code: String
    let p_amount_cents: Int
    let p_source: String
    let p_idempotency_key: String
    let p_display_name: String
    let p_payment_intent_id: UUID?
}

private struct HandDelta: Encodable {
    let player_key: String
    let delta_cents: Int
}

private struct RecordHandParams: Encodable {
    let p_invite_code: String
    let p_hand_id: String
    let p_deltas: [HandDelta]
}

private struct PokerActParams: Encodable {
    let p_invite_code: String
    let p_action: String
    let p_amount_cents: Int?
    let p_action_id: String
}

private struct LeaveTableParams: Encodable {
    let p_invite_code: String
    let p_idempotency_key: String
}

private struct WithdrawalParams: Encodable {
    let p_amount_cents: Int
    let p_idempotency_key: String
    let p_currency: String
}

private struct ResolveWithdrawalParams: Encodable {
    let p_withdrawal_id: UUID
    let p_outcome: String
}

// MARK: - Rows

private struct SummaryRow: Decodable {
    let currency_code: String
    let available_cents: Int
    let in_play_cents: Int
    let pending_deposit_cents: Int
    let pending_withdrawal_cents: Int
    let is_sandbox: Bool
    let deposit_min_cents: Int
    let deposit_max_cents: Int
    let withdrawal_min_cents: Int
    let withdrawal_fee_flat_cents: Int
    let withdrawal_fee_basis_points: Int
    let identity_status: String
    let payout_method_status: String
    let account_status: String
    let jurisdiction_status: String
    let self_excluded_until: Date?

    var model: VaultSummary {
        VaultSummary(
            currencyCode: currency_code,
            available: Money(cents: available_cents),
            inPlay: Money(cents: in_play_cents),
            pendingDeposits: Money(cents: pending_deposit_cents),
            pendingWithdrawals: Money(cents: pending_withdrawal_cents),
            isSandbox: is_sandbox,
            depositMinimum: Money(cents: deposit_min_cents),
            depositMaximum: Money(cents: deposit_max_cents),
            withdrawalMinimum: Money(cents: withdrawal_min_cents),
            withdrawalFeeFlat: Money(cents: withdrawal_fee_flat_cents),
            withdrawalFeeBasisPoints: withdrawal_fee_basis_points,
            identityStatus: IdentityStatus(rawValue: identity_status) ?? .unverified,
            payoutMethodStatus: PayoutMethodStatus(rawValue: payout_method_status) ?? .none,
            accountStatus: AccountStatus(rawValue: account_status) ?? .active,
            jurisdictionStatus: JurisdictionStatus(rawValue: jurisdiction_status) ?? .unknown,
            selfExcludedUntil: self_excluded_until
        )
    }
}

private struct StatementRow: Decodable {
    let id: UUID
    let reference_code: String
    let kind: String
    let status: String
    let amount_cents: Int
    let currency_code: String
    let table_invite_code: String?
    let is_demo: Bool
    let detail: String?
    let created_at: Date

    var model: VaultTransaction? {
        guard
            let kind = VaultTransactionKind(rawValue: kind),
            let status = VaultTransactionStatus(rawValue: status)
        else {
            return nil
        }

        return VaultTransaction(
            id: id,
            referenceCode: reference_code,
            kind: kind,
            status: status,
            amount: Money(cents: amount_cents),
            currencyCode: currency_code,
            tableInviteCode: table_invite_code,
            isDemo: is_demo,
            detail: detail,
            createdAt: created_at
        )
    }
}

private struct IntentRow: Decodable {
    let id: UUID
    let reference_code: String
    let amount_cents: Int
    let currency_code: String
    let status: String
    let purpose: String
    let table_invite_code: String?
    let is_demo: Bool
    let failure_reason: String?

    var model: DepositIntent {
        DepositIntent(
            id: id,
            referenceCode: reference_code,
            amount: Money(cents: amount_cents),
            currencyCode: currency_code,
            status: DepositIntentStatus(rawValue: status) ?? .failed,
            purpose: DepositPurpose(rawValue: purpose) ?? .vaultDeposit,
            tableInviteCode: table_invite_code,
            isDemo: is_demo,
            failureReason: failure_reason
        )
    }
}

private struct TableRow: Decodable {
    let invite_code: String
    let currency_code: String
    let min_buy_in_cents: Int
    let max_buy_in_cents: Int

    var model: TableBuyInLimits {
        TableBuyInLimits(
            inviteCode: invite_code,
            currencyCode: currency_code,
            minimum: Money(cents: min_buy_in_cents),
            maximum: Money(cents: max_buy_in_cents)
        )
    }
}

private struct BuyInRow: Decodable {
    let reference_code: String
    let invite_code: String
    let in_play_cents: Int
    let total_bought_in_cents: Int

    var model: TableBuyInReceipt {
        TableBuyInReceipt(
            referenceCode: reference_code,
            inviteCode: invite_code,
            inPlay: Money(cents: in_play_cents),
            totalBoughtIn: Money(cents: total_bought_in_cents)
        )
    }
}

private struct ChipRow: Decodable {
    let player_key: String
    let display_name: String
    let in_play_cents: Int

    var model: TableChipCount {
        TableChipCount(
            playerKey: player_key,
            displayName: display_name,
            inPlay: Money(cents: in_play_cents)
        )
    }
}

private struct HandResultRow: Decodable {
    let status: String
    let reference_code: String?
}

private struct SettlementRow: Decodable {
    let invite_code: String
    let bought_in_cents: Int
    let returned_cents: Int
    let reference_code: String
    let already_settled: Bool
    let table_currency: String?
    let wallet_returned_cents: Int?
    let wallet_currency: String?

    var model: TableSettlement {
        TableSettlement(
            inviteCode: invite_code,
            boughtIn: Money(cents: bought_in_cents),
            returned: Money(cents: returned_cents),
            referenceCode: reference_code,
            alreadySettled: already_settled,
            tableCurrencyCode: table_currency ?? wallet_currency ?? "USD",
            walletReturned: wallet_returned_cents.map(Money.init(cents:)),
            walletCurrencyCode: wallet_currency
        )
    }
}

private struct WithdrawalRow: Decodable {
    let id: UUID
    let reference_code: String
    let amount_cents: Int
    let fee_cents: Int
    let net_cents: Int
    let currency_code: String
    let status: String
    let is_demo: Bool
    let failure_reason: String?
    let requested_at: Date

    var model: WithdrawalRequest {
        WithdrawalRequest(
            id: id,
            referenceCode: reference_code,
            amount: Money(cents: amount_cents),
            fee: Money(cents: fee_cents),
            net: Money(cents: net_cents),
            currencyCode: currency_code,
            status: WithdrawalStatus(rawValue: status) ?? .pending,
            isDemo: is_demo,
            failureReason: failure_reason,
            requestedAt: requested_at
        )
    }
}
