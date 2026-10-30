import CoreML
import Foundation

/// A problem paired with the model's confidence that it's a good learning opportunity.
struct ScoredProblem: Identifiable {
    var id: String { problem.id }
    let problem: Problem
    /// Model probability that this problem is recommended (0 = skip, 1 = perfect fit).
    let score: Double
}

/// On-device recommendation engine powered by the Core ML model.
///
/// Converts a user's submission history into a feature vector per unsolved problem,
/// runs each through the trained Random Forest, and returns the top-scoring results.
final class RecommendationEngine {

    static let shared = RecommendationEngine()

    // All 38 CF topic tags — must stay in sync with whatever was used during training.
    // These are the alphabetically sorted unique tags from the CF problem catalog.
    static let cfTags: [String] = [
        "*special", "2-sat", "binary search", "bitmasks", "brute force",
        "chinese remainder theorem", "combinatorics", "communication",
        "constructive algorithms", "data structures", "dfs and similar",
        "divide and conquer", "dp", "dsu", "expression parsing", "fft",
        "flows", "games", "geometry", "graph matchings", "graphs", "greedy",
        "hashing", "implementation", "interactive", "math", "matrices",
        "meet-in-the-middle", "number theory", "probabilities", "schedules",
        "shortest paths", "sortings", "string suffix structures", "strings",
        "ternary search", "trees", "two pointers"
    ]

    private let mlModel: MLModel

    private init() {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine
        do {
            mlModel = try ProblemRecommender1(configuration: config).model
        } catch {
            fatalError("RecommendationEngine: could not load model — \(error)")
        }
    }

    /// Ranks unsolved problems by learning opportunity for the given user.
    /// - Parameters:
    ///   - problems: Full CF problem catalog.
    ///   - userRating: User's current Codeforces rating.
    ///   - submissions: User's submission history.
    ///   - topN: Maximum number of results to return.
    /// - Returns: Array of `ScoredProblem` sorted by score descending.
    func recommend(
        problems: [Problem],
        userRating: Int,
        submissions: [Submission],
        topN: Int = 20
    ) throws -> [ScoredProblem] {

        // Step 1: build a set of problems the user has already solved
        // so we never recommend something they've already accepted.
        let solvedKeys: Set<String> = Set(
            submissions
                .filter { $0.verdict == .ok }
                .compactMap { sub -> String? in
                    guard let cid = sub.problem.contestId,
                          let idx = sub.problem.index else { return nil }
                    return "\(cid)-\(idx)"
                }
        )

        // Step 2: compute per-tag success rate from the user's history.
        // success_rate[tag] = accepted_count / attempt_count for that tag.
        // This is the core personalisation signal — a user who rarely accepts
        // "graphs" problems gets more graph recommendations to improve that weakness.
        var tagAttempts: [String: Int] = [:]
        var tagAccepted: [String: Int] = [:]

        for sub in submissions {
            for tag in sub.problem.tags ?? [] {
                tagAttempts[tag, default: 0] += 1
                if sub.verdict == .ok {
                    tagAccepted[tag, default: 0] += 1
                }
            }
        }

        var tagSuccess: [String: Double] = [:]
        for (tag, attempts) in tagAttempts {
            tagSuccess[tag] = Double(tagAccepted[tag, default: 0]) / Double(attempts)
        }

        // Step 3: build a feature vector for each unsolved problem and run inference.
        var scored: [ScoredProblem] = []

        for problem in problems {
            let key = "\(problem.contestId)-\(problem.index)"
            guard !solvedKeys.contains(key), let rating = problem.rating else { continue }

            // diff_delta: how far the problem's rating is from the user's rating.
            // Positive = harder than user, negative = easier.
            // The model learned that problems ~0-300 above user rating are best.
            var features: [String: MLFeatureValue] = [
                "diff_delta":    MLFeatureValue(double: Double(rating - userRating)),
                "solved_before": MLFeatureValue(double: 0.0),
                // solvers_norm is the fraction of all CF users who solved this problem.
                // The Problem model doesn't carry this field, so we use 0.5 as neutral.
                "solvers_norm":  MLFeatureValue(double: 0.5)
            ]

            // One-hot encode which tags the problem has (tag_dp = 1 if it's a DP problem)
            // and attach the user's success rate for each tag (success_dp = 0.4 means
            // the user accepts 40% of DP problems they attempt).
            for tag in Self.cfTags {
                let col = safeCol(tag)
                features["tag_\(col)"]     = MLFeatureValue(double: problem.tags.contains(tag) ? 1.0 : 0.0)
                features["success_\(col)"] = MLFeatureValue(double: tagSuccess[tag] ?? 0.5)
            }

            // We use MLDictionaryFeatureProvider instead of the auto-generated
            // ProblemRecommender1Input struct because one tag name ("*special")
            // contains a character that isn't valid in a Swift identifier.
            let provider = try MLDictionaryFeatureProvider(dictionary: features)
            let output   = try mlModel.prediction(from: provider)

            // The model outputs a probability dict with NSNumber keys (0 and 1)
            // because the training labels were integers, not strings.
            if let probs = output.featureValue(for: "recommendedProbability")?.dictionaryValue,
               let prob = probs[1 as NSNumber] as? Double {
                scored.append(ScoredProblem(problem: problem, score: prob))
            }
        }

        // Step 4: return the top N problems sorted by recommendation confidence.
        return Array(scored.sorted { $0.score > $1.score }.prefix(topN))
    }

    // Converts a raw CF tag name to its column-name equivalent used during training.
    // Spaces, hyphens, and slashes become underscores.
    // e.g. "two pointers" -> "two_pointers", "meet-in-the-middle" -> "meet_in_the_middle"
    private func safeCol(_ tag: String) -> String {
        tag
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: "/", with: "_")
    }
}
