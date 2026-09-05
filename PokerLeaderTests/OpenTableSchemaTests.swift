import XCTest
@testable import PokerLeader

final class OpenTableSchemaTests: XCTestCase {
    private struct CloudError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private func error(_ message: String) -> Error {
        CloudError(message: message)
    }

    func testAMissingHandColumnIsToldApartFromAMissingTable() {
        let missingColumn = error("Could not find the 'hand' column of 'open_tables' in the schema cache")

        XCTAssertTrue(OpenTableSchema.isMissingHandColumn(missingColumn))
        XCTAssertFalse(
            OpenTableSchema.isMissingTable(missingColumn),
            "The table is there, so the host should not be sent back to the first migration"
        )
    }

    func testAMissingAnteColumnIsRecognised() {
        XCTAssertTrue(
            OpenTableSchema.isMissingHandColumn(
                error("Could not find the 'ante_amount' column of 'open_tables' in the schema cache")
            )
        )
    }

    func testAMissingTableIsStillRecognised() {
        let missingTable = error("Could not find the table 'public.open_tables' in the schema cache")

        XCTAssertTrue(OpenTableSchema.isMissingTable(missingTable))
        XCTAssertFalse(OpenTableSchema.isMissingHandColumn(missingTable))
    }

    func testUnrelatedFailuresAreLeftAlone() {
        let offline = error("The Internet connection appears to be offline.")

        XCTAssertFalse(OpenTableSchema.isMissingTable(offline))
        XCTAssertFalse(OpenTableSchema.isMissingHandColumn(offline))
    }
}
