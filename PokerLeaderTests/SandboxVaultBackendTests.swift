import XCTest
@testable import PokerLeader

/// Walks the demo backend through the same money path the SQL tests put the
/// real one through, and checks the invariants that matter: a payment is only
/// worth something once it has been verified, a request replayed cannot move
/// money twice, a balance cannot go negative, and every movement is on the
/// statement.
@MainActor
final class SandboxVaultBackendTests: XCTestCase {
    private var vault: SandboxVaultBackend { SandboxVaultBackend.shared }

    override func setUp() async throws {
        vault.reset()
    }

    override func tearDown() async throws {
        vault.reset()
    }

    private func deposit(_ amount: Money, key: String) async throws {
        let intent = try await vault.createDepositIntent(
            amount: amount,
            purpose: .vaultDeposit,
            tableInviteCode: nil,
            idempotencyKey: key
        )
        _ = try await vault.confirmDeposit(intentID: intent.id)
    }

    // MARK: - Deposits

    func testMoneyIsNotSpendableUntilTheBackendVerifiesIt() async throws {
        let intent = try await vault.createDepositIntent(
            amount: Money(cents: 10_000),
            purpose: .vaultDeposit,
            tableInviteCode: nil,
            idempotencyKey: "dep-1"
        )

        var summary = try await vault.summary()
        XCTAssertEqual(summary.available, .zero)
        XCTAssertEqual(summary.pendingDeposits, Money(cents: 10_000))

        _ = try await vault.confirmDeposit(intentID: intent.id)

        summary = try await vault.summary()
        XCTAssertEqual(summary.available, Money(cents: 10_000))
        XCTAssertEqual(summary.pendingDeposits, .zero)
    }

    func testConfirmingTheSameDepositTwiceCreditsItOnce() async throws {
        let intent = try await vault.createDepositIntent(
            amount: Money(cents: 5_000),
            purpose: .vaultDeposit,
            tableInviteCode: nil,
            idempotencyKey: "dep-1"
        )
        _ = try await vault.confirmDeposit(intentID: intent.id)
        _ = try await vault.confirmDeposit(intentID: intent.id)

        let summary = try await vault.summary()
        XCTAssertEqual(summary.available, Money(cents: 5_000))
    }

    func testADeclinedDepositAddsNothingAndStaysOnTheStatement() async throws {
        let intent = try await vault.createDepositIntent(
            amount: Money(cents: 3_000),
            purpose: .vaultDeposit,
            tableInviteCode: nil,
            idempotencyKey: "dep-1"
        )
        _ = try await vault.cancelDeposit(intentID: intent.id)

        let summary = try await vault.summary()
        XCTAssertEqual(summary.available, .zero)

        let statement = try await vault.transactions(limit: 10)
        XCTAssertTrue(statement.contains { $0.kind == .deposit && $0.status == .canceled })
    }

    // MARK: - Table buy-ins

    func testAVaultBuyInMovesMoneyIntoPlayWithoutChangingTheTotal() async throws {
        try await deposit(Money(cents: 10_000), key: "dep-1")
        _ = try await vault.registerTable(
            inviteCode: "ABC123",
            minimum: Money(cents: 2_000),
            maximum: Money(cents: 8_000),
            currencyCode: "USD"
        )

        let receipt = try await vault.buyIn(
            inviteCode: "ABC123",
            amount: Money(cents: 4_000),
            source: .vault,
            playerKey: "me",
            displayName: "Me",
            paymentIntentID: nil,
            idempotencyKey: "buy-1"
        )

        XCTAssertEqual(receipt.inPlay, Money(cents: 4_000))

        let summary = try await vault.summary()
        XCTAssertEqual(summary.available, Money(cents: 6_000))
        XCTAssertEqual(summary.inPlay, Money(cents: 4_000))
        XCTAssertEqual(summary.total, Money(cents: 10_000))
    }

    func testAReplayedBuyInDoesNotChargeTwice() async throws {
        try await deposit(Money(cents: 10_000), key: "dep-1")
        _ = try await vault.registerTable(
            inviteCode: "ABC123",
            minimum: Money(cents: 2_000),
            maximum: Money(cents: 8_000),
            currencyCode: "USD"
        )

        for _ in 0..<3 {
            _ = try await vault.buyIn(
                inviteCode: "ABC123",
                amount: Money(cents: 4_000),
                source: .vault,
                playerKey: "me",
                displayName: "Me",
                paymentIntentID: nil,
                idempotencyKey: "buy-1"
            )
        }

        let summary = try await vault.summary()
        XCTAssertEqual(summary.available, Money(cents: 6_000))
        XCTAssertEqual(summary.inPlay, Money(cents: 4_000))
    }

    func testABuyInBeyondTheVaultBalanceIsRefused() async throws {
        try await deposit(Money(cents: 3_000), key: "dep-1")
        _ = try await vault.registerTable(
            inviteCode: "ABC123",
            minimum: Money(cents: 1_000),
            maximum: Money(cents: 8_000),
            currencyCode: "USD"
        )

        do {
            _ = try await vault.buyIn(
                inviteCode: "ABC123",
                amount: Money(cents: 5_000),
                source: .vault,
                playerKey: "me",
                displayName: "Me",
                paymentIntentID: nil,
                idempotencyKey: "buy-1"
            )
            XCTFail("A buy-in bigger than the Vault should be refused")
        } catch {
            XCTAssertEqual(VaultError.from(error), .insufficientFunds)
        }

        let summary = try await vault.summary()
        XCTAssertEqual(summary.available, Money(cents: 3_000))
        XCTAssertEqual(summary.inPlay, .zero)
    }

    func testABuyInOutsideTheTableRangeIsRefused() async throws {
        try await deposit(Money(cents: 50_000), key: "dep-1")
        _ = try await vault.registerTable(
            inviteCode: "ABC123",
            minimum: Money(cents: 2_000),
            maximum: Money(cents: 8_000),
            currencyCode: "USD"
        )

        for amount in [Money(cents: 500), Money(cents: 20_000)] {
            do {
                _ = try await vault.buyIn(
                    inviteCode: "ABC123",
                    amount: amount,
                    source: .vault,
                    playerKey: "me",
                    displayName: "Me",
                    paymentIntentID: nil,
                    idempotencyKey: "buy-\(amount.cents)"
                )
                XCTFail("\(amount.cents) is outside the table's range")
            } catch {
                // Expected.
            }
        }
    }

    func testAnUnverifiedPaymentCannotBuyASeat() async throws {
        _ = try await vault.registerTable(
            inviteCode: "ABC123",
            minimum: Money(cents: 1_000),
            maximum: Money(cents: 8_000),
            currencyCode: "USD"
        )
        let intent = try await vault.createDepositIntent(
            amount: Money(cents: 2_000),
            purpose: .tableBuyIn,
            tableInviteCode: "ABC123",
            idempotencyKey: "pay-1"
        )

        do {
            _ = try await vault.buyIn(
                inviteCode: "ABC123",
                amount: Money(cents: 2_000),
                source: .applePay,
                playerKey: "me",
                displayName: "Me",
                paymentIntentID: intent.id,
                idempotencyKey: "buy-1"
            )
            XCTFail("A payment nobody has verified should not seat anyone")
        } catch {
            // Expected.
        }

        let summary = try await vault.summary()
        XCTAssertEqual(summary.inPlay, .zero)
    }

    func testAVerifiedPaymentCanOnlyBeSpentOnce() async throws {
        _ = try await vault.registerTable(
            inviteCode: "ABC123",
            minimum: Money(cents: 1_000),
            maximum: Money(cents: 8_000),
            currencyCode: "USD"
        )
        let intent = try await vault.createDepositIntent(
            amount: Money(cents: 2_000),
            purpose: .tableBuyIn,
            tableInviteCode: "ABC123",
            idempotencyKey: "pay-1"
        )
        _ = try await vault.confirmDeposit(intentID: intent.id)

        _ = try await vault.buyIn(
            inviteCode: "ABC123",
            amount: Money(cents: 2_000),
            source: .applePay,
            playerKey: "me",
            displayName: "Me",
            paymentIntentID: intent.id,
            idempotencyKey: "buy-1"
        )

        do {
            _ = try await vault.buyIn(
                inviteCode: "ABC123",
                amount: Money(cents: 2_000),
                source: .applePay,
                playerKey: "me",
                displayName: "Me",
                paymentIntentID: intent.id,
                idempotencyKey: "buy-2"
            )
            XCTFail("The same payment should not buy two seats")
        } catch {
            // Expected.
        }

        let summary = try await vault.summary()
        XCTAssertEqual(summary.inPlay, Money(cents: 2_000))
    }

    func testADirectPaymentGoesStraightIntoPlay() async throws {
        _ = try await vault.registerTable(
            inviteCode: "ABC123",
            minimum: Money(cents: 1_000),
            maximum: Money(cents: 8_000),
            currencyCode: "USD"
        )
        let intent = try await vault.createDepositIntent(
            amount: Money(cents: 2_000),
            purpose: .tableBuyIn,
            tableInviteCode: "ABC123",
            idempotencyKey: "pay-1"
        )
        _ = try await vault.confirmDeposit(intentID: intent.id)
        _ = try await vault.buyIn(
            inviteCode: "ABC123",
            amount: Money(cents: 2_000),
            source: .applePay,
            playerKey: "me",
            displayName: "Me",
            paymentIntentID: intent.id,
            idempotencyKey: "buy-1"
        )

        let summary = try await vault.summary()
        XCTAssertEqual(summary.available, .zero, "A direct buy-in never passes through the balance")
        XCTAssertEqual(summary.inPlay, Money(cents: 2_000))
    }

    // MARK: - Hands and leaving

    func testAClientSuppliedHandResultIsRefused() async throws {
        try await seatWithChips(Money(cents: 4_000))

        do {
            try await vault.recordHand(
                inviteCode: "ABC123",
                handID: "hand-1",
                deltas: ["me": Money(cents: 1_500)]
            )
            XCTFail("A fabricated hand result must be refused")
        } catch {
            let message = error.localizedDescription.lowercased()
            XCTAssertTrue(message.contains("server") || message.contains("action") || message.contains("result"))
        }

        let chips = try await vault.tableChips(inviteCode: "ABC123")
        XCTAssertEqual(chips.first?.inPlay, Money(cents: 4_000), "Refusing the result must not move chips")
    }

    func testLeavingReturnsWhatTheBackendSaysTheSeatHolds() async throws {
        try await seatWithChips(Money(cents: 4_000))

        let settlement = try await vault.leaveTable(inviteCode: "ABC123", idempotencyKey: "leave-1")
        XCTAssertEqual(settlement.boughtIn, Money(cents: 4_000))
        XCTAssertEqual(settlement.returned, Money(cents: 4_000))
        XCTAssertEqual(settlement.net, .zero)
        XCTAssertFalse(settlement.alreadySettled)

        let summary = try await vault.summary()
        XCTAssertEqual(summary.inPlay, .zero)
        XCTAssertEqual(summary.available, Money(cents: 10_000))
    }

    func testLeavingTwiceReportsTheSameFiguresAndMovesNothing() async throws {
        try await seatWithChips(Money(cents: 4_000))
        _ = try await vault.leaveTable(inviteCode: "ABC123", idempotencyKey: "leave-1")
        let second = try await vault.leaveTable(inviteCode: "ABC123", idempotencyKey: "leave-1")

        XCTAssertTrue(second.alreadySettled)
        XCTAssertEqual(second.returned, Money(cents: 4_000))

        let summary = try await vault.summary()
        XCTAssertEqual(summary.available, Money(cents: 10_000))
    }

    // MARK: - Cash-outs

    func testACashOutReservesTheMoneyWithoutChangingTheTotal() async throws {
        try await deposit(Money(cents: 10_000), key: "dep-1")
        _ = try await vault.requestWithdrawal(amount: Money(cents: 4_000), idempotencyKey: "co-1")

        let summary = try await vault.summary()
        XCTAssertEqual(summary.available, Money(cents: 6_000))
        XCTAssertEqual(summary.pendingWithdrawals, Money(cents: 4_000))
        XCTAssertEqual(summary.total, Money(cents: 10_000))
        XCTAssertEqual(summary.withdrawable, Money(cents: 6_000))
    }

    func testMoneyInPlayCannotBeCashedOut() async throws {
        try await seatWithChips(Money(cents: 8_000))

        do {
            _ = try await vault.requestWithdrawal(amount: Money(cents: 5_000), idempotencyKey: "co-1")
            XCTFail("Chips on a table are not withdrawable")
        } catch {
            // Expected.
        }
    }

    func testAPaidCashOutLeavesTheVault() async throws {
        try await deposit(Money(cents: 10_000), key: "dep-1")
        let request = try await vault.requestWithdrawal(amount: Money(cents: 4_000), idempotencyKey: "co-1")
        _ = try await vault.settleWithdrawalInSandbox(id: request.id, succeeds: true)

        let summary = try await vault.summary()
        XCTAssertEqual(summary.pendingWithdrawals, .zero)
        XCTAssertEqual(summary.total, Money(cents: 6_000))
    }

    func testAUSDBuyInOnAGBPTableConvertsThenTransfers() async throws {
        try await deposit(Money(cents: 10_000), key: "dep-1")
        _ = try await vault.registerTable(
            inviteCode: "GBP1",
            minimum: Money(cents: 1_000),
            maximum: Money(cents: 8_000),
            currencyCode: "GBP"
        )

        let receipt = try await vault.buyIn(
            inviteCode: "GBP1",
            amount: Money(cents: 2_000),
            source: .vault,
            playerKey: "me",
            displayName: "Me",
            paymentIntentID: nil,
            idempotencyKey: "buy-gbp"
        )

        let charged = try XCTUnwrap(VaultFX.convert(cents: 2_000, from: "GBP", to: "USD"))
        XCTAssertEqual(receipt.inPlay, Money(cents: 2_000))

        var summary = try await vault.summary()
        XCTAssertEqual(summary.available, Money(cents: 10_000 - charged))
        XCTAssertEqual(summary.inPlay, Money(cents: charged))
        XCTAssertEqual(summary.total, Money(cents: 10_000))

        let settlement = try await vault.leaveTable(inviteCode: "GBP1", idempotencyKey: "leave-gbp")
        XCTAssertEqual(settlement.boughtIn, Money(cents: 2_000))
        XCTAssertEqual(settlement.returned, Money(cents: 2_000))
        XCTAssertEqual(settlement.walletReturned, Money(cents: charged))
        XCTAssertEqual(settlement.tableCurrencyCode, "GBP")

        summary = try await vault.summary()
        XCTAssertEqual(summary.available, Money(cents: 10_000))
        XCTAssertEqual(summary.inPlay, .zero)
    }

    func testAUSDVaultCanWithdrawInGBP() async throws {
        try await deposit(Money(cents: 10_000), key: "dep-1")

        let request = try await vault.requestWithdrawal(
            amount: Money(cents: 7_900),
            currencyCode: "GBP",
            idempotencyKey: "co-gbp"
        )

        XCTAssertEqual(request.amount, Money(cents: 7_900))
        XCTAssertEqual(request.currencyCode, "GBP")
        XCTAssertEqual(request.net, Money(cents: 7_900))

        var summary = try await vault.summary()
        XCTAssertEqual(summary.available, .zero)
        XCTAssertEqual(summary.pendingWithdrawals, Money(cents: 10_000))
        XCTAssertEqual(summary.total, Money(cents: 10_000))

        _ = try await vault.settleWithdrawalInSandbox(id: request.id, succeeds: true)

        summary = try await vault.summary()
        XCTAssertEqual(summary.available, .zero)
        XCTAssertEqual(summary.pendingWithdrawals, .zero)
        XCTAssertEqual(summary.total, .zero)
    }

    func testACanceledCashOutComesBack() async throws {
        try await deposit(Money(cents: 10_000), key: "dep-1")
        let request = try await vault.requestWithdrawal(amount: Money(cents: 4_000), idempotencyKey: "co-1")
        _ = try await vault.cancelWithdrawal(id: request.id)

        let summary = try await vault.summary()
        XCTAssertEqual(summary.available, Money(cents: 10_000))
        XCTAssertEqual(summary.pendingWithdrawals, .zero)
    }

    // MARK: - Statement

    func testEveryMovementIsOnTheStatementAndLabelledAsDemoMoney() async throws {
        try await seatWithChips(Money(cents: 4_000))
        _ = try await vault.leaveTable(inviteCode: "ABC123", idempotencyKey: "leave-1")
        let request = try await vault.requestWithdrawal(amount: Money(cents: 2_000), idempotencyKey: "co-1")
        _ = try await vault.settleWithdrawalInSandbox(id: request.id, succeeds: true)

        let statement = try await vault.transactions(limit: 100)
        let kinds = Set(statement.map(\.kind))

        XCTAssertTrue(kinds.contains(.deposit))
        XCTAssertTrue(kinds.contains(.tableBuyInVault))
        XCTAssertTrue(kinds.contains(.tableReturn))
        XCTAssertTrue(kinds.contains(.withdrawalRequest))
        XCTAssertTrue(kinds.contains(.withdrawalCompleted))
        XCTAssertTrue(statement.allSatisfy(\.isDemo))
        XCTAssertTrue(statement.allSatisfy { !$0.referenceCode.isEmpty })
    }

    // MARK: - Helpers

    private func seatWithChips(_ amount: Money) async throws {
        try await deposit(Money(cents: 10_000), key: "dep-1")
        _ = try await vault.registerTable(
            inviteCode: "ABC123",
            minimum: Money(cents: 1_000),
            maximum: Money(cents: 9_000),
            currencyCode: "USD"
        )
        _ = try await vault.buyIn(
            inviteCode: "ABC123",
            amount: amount,
            source: .vault,
            playerKey: "me",
            displayName: "Me",
            paymentIntentID: nil,
            idempotencyKey: "buy-1"
        )
    }
}
