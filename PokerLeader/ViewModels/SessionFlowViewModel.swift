import Foundation
import SwiftData

/// Coordinates live session UI state. Repositories persist changes.
@Observable
@MainActor
final class SessionFlowViewModel {
    private let sessionRepository: SessionRepository

    init(context: ModelContext) {
        self.sessionRepository = SessionRepository(context: context)
    }

    func addBuyIn(player: SessionPlayerModel, session: SessionModel) {
        sessionRepository.addBuyIn(player: player, amount: session.buyInAmount, session: session)
    }

    func settle(session: SessionModel) {
        sessionRepository.settle(session: session)
    }
}
