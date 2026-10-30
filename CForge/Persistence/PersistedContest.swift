import Foundation
import SwiftData

// MARK: - PersistedContest
//
// SwiftData mirror of the `CFContest` domain struct.
// Repositories write here; the offline-first read path (Issue 11) reads from here.
//
// Schema v1 → v2 migration strategy: deleteAll (data is always re-fetchable from CF API)

@Model
final class PersistedContest {

    @Attribute(.unique) var id: Int
    var name: String
    var type: String
    var phase: String
    var startTimeSeconds: Int
    var durationSeconds: Int
    var updatedAt: Date

    init(from domain: CFContest) {
        self.id               = domain.id
        self.name             = domain.name
        self.type             = domain.type
        self.phase            = domain.phase
        self.startTimeSeconds = domain.startTimeSeconds ?? 0
        self.durationSeconds  = domain.durationSeconds
        self.updatedAt        = Date()
    }

    func toDomain() -> CFContest {
        CFContest(
            id:                id,
            name:              name,
            type:              type,
            phase:             phase,
            durationSeconds:   durationSeconds,
            startTimeSeconds:  startTimeSeconds
        )
    }
}
