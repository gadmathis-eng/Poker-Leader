import SwiftData

enum ModelContainerSetup {
    static func makeContainer() -> ModelContainer {
        let schema = Schema([
            CircleModel.self,
            MemberModel.self,
            SessionModel.self,
            SessionPlayerModel.self,
            SettlementPaymentModel.self,
            FriendRequestModel.self,
            AppNotificationModel.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
