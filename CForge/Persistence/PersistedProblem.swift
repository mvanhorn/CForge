import Foundation
import SwiftData

// MARK: - PersistedProblem
//
// SwiftData mirror of the `ApiProblem` domain struct.
// Unique key: composite string "\(contestId)-\(index)" since neither field
// alone is globally unique.

@Model
final class PersistedProblem {

    /// Composite unique key: "<contestId>-<index>" e.g. "1234-A"
    @Attribute(.unique) var key: String
    var contestId: Int?
    var index: String?
    var name: String?
    var rating: Int?
    var tags: [String]
    var updatedAt: Date

    init(from domain: ApiProblem) {
        self.contestId = domain.contestId
        self.index     = domain.index
        self.name      = domain.name
        self.rating    = domain.rating
        self.tags      = domain.tags ?? []
        self.key       = "\(domain.contestId ?? 0)-\(domain.index ?? "")"
        self.updatedAt = Date()
    }

    func toDomain() -> ApiProblem {
        ApiProblem(
            contestId: contestId,
            index:     index,
            name:      name,
            rating:    rating,
            tags:      tags
        )
    }
}
