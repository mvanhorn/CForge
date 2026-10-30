import Foundation
import SwiftData

// MARK: - PersistedRatingChange
//
// SwiftData mirror of the `RatingChange` domain struct.
// Unique key: contestId (one rating change per contest per user).

@Model
final class PersistedRatingChange {

    @Attribute(.unique) var contestId: Int
    var contestName: String
    var handle: String
    var rank: Int
    var ratingUpdateTimeSeconds: Int
    var oldRating: Int
    var newRating: Int

    init(from domain: RatingChange) {
        self.contestId               = domain.contestId
        self.contestName             = domain.contestName
        self.handle                  = domain.handle
        self.rank                    = domain.rank
        self.ratingUpdateTimeSeconds = domain.ratingUpdateTimeSeconds
        self.oldRating               = domain.oldRating
        self.newRating               = domain.newRating
    }

    func toDomain() -> RatingChange {
        RatingChange(
            contestId:               contestId,
            contestName:             contestName,
            handle:                  handle,
            rank:                    rank,
            ratingUpdateTimeSeconds: ratingUpdateTimeSeconds,
            oldRating:               oldRating,
            newRating:               newRating
        )
    }
}
