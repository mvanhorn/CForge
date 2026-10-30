import SwiftData

// MARK: - PersistenceController
//
// Singleton that vends the app's shared ModelContainer.
// Repositories create their own actor-isolated ModelContext from this container —
// ModelContainer itself is thread-safe; ModelContext is not, so each actor owns one.

struct PersistenceController {

    static let shared = PersistenceController()

    let container: ModelContainer

    private static let schema = Schema([
        PersistedContest.self,
        PersistedProblem.self,
        PersistedRatingChange.self
    ])

    /// Production init — stores to disk.
    init(inMemory: Bool = false) {
        let config = ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(for: Self.schema, configurations: [config])
        } catch {
            fatalError("SwiftData: Could not create ModelContainer — \(error)")
        }
    }

    /// In-memory container for Xcode Previews and unit tests.
    static let preview = PersistenceController(inMemory: true)
}
