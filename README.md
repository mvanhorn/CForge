# CForge: Codeforces Companion for iOS

A native iOS client for Codeforces with an **on-device ML recommendation engine** that ranks problems by learning opportunity, live contest tracking, and real-time submission verdicts via WebSocket.

![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)
![iOS](https://img.shields.io/badge/iOS-17%2B-blue?logo=apple)
![Core ML](https://img.shields.io/badge/Core%20ML-on--device-purple)
![SwiftLint](https://img.shields.io/badge/SwiftLint-enabled-green)
![Architecture](https://img.shields.io/badge/Architecture-MVVM%20%2B%20Repository-lightgrey)

## Screenshots

<table>
<tr>

<td width="33%" align="center"><b>Splash Screen</b><br>
<img src="https://github.com/user-attachments/assets/3cf4e1a8-fca4-4e5d-b673-62fdf1d7feb3" width="100%">
</td>

<td width="33%" align="center"><b>Login Screen</b><br>
<img src="https://github.com/user-attachments/assets/a2eadb1b-0173-404e-871d-a1591bed3af1" width="100%">
</td>

<td width="33%" align="center"><b>Contests</b><br>
<img src="https://github.com/user-attachments/assets/8421d0a1-c12a-400a-9d5e-a7a2ead8d878" width="100%">
</td>

</tr>
<tr>

<td width="33%" align="center"><b>Problems</b><br>
<img src="https://github.com/user-attachments/assets/1d281dd1-caa2-4fc5-9b6d-0405a3eb478b" width="100%">
</td>

<td width="33%" align="center"><b>For You</b><br>
<img src="https://github.com/user-attachments/assets/6a97810b-bd6e-441e-8967-ef6454e38be0" width="100%">
</td>

<td width="33%" align="center"><b>Profile</b><br>
<img src="https://github.com/user-attachments/assets/d3ee8d8b-8be5-44ca-ae74-9cf93b0e56a3" width="100%">
</td>

</tr>
</table>


## Features

- **For You** - On-device ML model ranks unsolved problems by personal weak spots and optimal difficulty gap
- **Live Verdicts** - WebSocket pushes submission results in real time without polling
- **Contest Tracker** - Upcoming and running contests with countdown timers
- **Problem Explorer** - Full problem set with search and tag filtering
- **Profile Insights** - Rating history chart, rank, and solve statistics

## ML Architecture: For You Tab

The recommendation engine runs fully on-device. No user data leaves the phone.

### Data Pipeline

```
Raw Codeforces submissions (HuggingFace dataset)
        |
        v
Feature Engineering  --  55,750 (user, problem) pairs · 1,115 users · 80 features
        |
        v
Create ML  --  Random Forest Classifier (100 trees, 100 iterations)
        |
        v
ProblemRecommender1.mlmodel  --  2.1 MB · on-device via Core ML
```

### Feature Set (per user-problem pair)

| Feature | Description |
|---|---|
| `diff_delta` | Problem rating minus user's current rating |
| `solved_before` | Whether the user has previously attempted this problem |
| `solvers_norm` | Normalised global acceptance count |
| `tag_*` (x38) | One-hot encoding of CF topic tags |
| `success_*` (x38) | User's per-tag acceptance rate from submission history |

### Results

| Metric | Value |
|---|---|
| Training samples | 55,750 |
| Users in dataset | 1,115 |
| Validation accuracy | 99% |
| Model size | 2.1 MB |
| Inference | On-device, <1s for full catalog |

The tag success-rate features are the personalisation signal. A user with low `success_graphs` acceptance gets more graph problems recommended to close that gap.

## Technical Architecture

### Layer Stack

```
┌──────────────────────────────────────────────────────────────┐
│                    SwiftUI Views                             │
│        @MainActor · Combine @Published bindings              │
└─────────────────────────────────┬────────────────────────────┘
                                  │  async/await + Combine
┌─────────────────────────────────▼────────────────────────────┐
│                     ViewModels                               │
│        @MainActor final class · ObservableObject             │
└────────┬─────────────────────────────────────────────────────┘
         │  actor-isolated calls
┌────────▼─────────────────────────────────────────────────────┐
│                    Repositories                              │
│    Swift actor · TTL cache · in-flight deduplication         │
│    Combine PassthroughSubject for real-time events           │
└────────┬──────────────────────────────────┬──────────────────┘
         │                                  │
┌────────▼────────────────────┐   ┌─────────▼────────────────────┐
│     Services                │   │      WebSocket Service       │
│  URLSession                 │   │  URLSessionWebSocketTask     │
│  RequestScheduler           │   │  typed event stream          │
└────────┬────────────────────┘   └─────────┬────────────────────┘
         │                                  │
┌────────▼────────────────────┐   ┌─────────▼────────────────────┐
│  Codeforces API             │   │      SwiftData Store         │
│  (REST JSON)                │   │  problems · rating · contest │
└─────────────────────────────┘   └──────────────────────────────┘


  On-device ML 

┌──────────────────────────────────────────────────────┐
│  RecommendationEngine                                │
│  Input:  [Problem] catalog + [Submission] history    │
│  Engine: MLDictionaryFeatureProvider → Core ML       │
│  Output: [ScoredProblem] ranked by P(recommended=1)  │
└──────────────────────────────────────────────────────┘
```

### Concurrency

All async work in CForge is structured around Swift's actor model and `async/await`. There are no raw `DispatchQueue` calls or completion handler chains.

- **ViewModels** are `@MainActor final class`: UI state mutations are always on the main thread without manual dispatch
- **Repositories** are Swift `actor`s: all internal state (`cache`, `ongoingTasks`) is actor-isolated, making concurrent reads safe by construction
- **`RequestScheduler`** is a dedicated actor that serialises outgoing API calls to respect the Codeforces rate limit (1 request per 2 seconds). All network calls go through it.
- **In-flight deduplication**: if two callers request the same resource simultaneously, the Repository creates one `Task<[T], Error>` and both `await` its value. No duplicate network calls.

### Reactive Bindings (Combine)

Repositories expose `AnyPublisher` streams for events that need to propagate without the caller polling:

| Publisher | Type | Consumed by |
|---|---|---|
| `ratingUpdated` | `AnyPublisher<(String, Int), Never>` | `ProfileViewModel` overlays live rating |
| `wsConnectionState` | `AnyPublisher<WebSocketConnectionState, Never>` | `ProfileViewModel` drives connection pill |
| `dataLastUpdated` | `AnyPublisher<Date, Never>` | `ProfileViewModel` drives staleness banner |
| `verdictReceived` | `AnyPublisher<Submission, Never>` | `ProfileViewModel` triggers verdict toast |

The WebSocket service emits a typed `WebSocketEvent` enum (`submissionVerdict`, `connectionStateChanged`). The `SubmissionRepository` subscribes, throttles at 500ms to prevent UI stutter during judge-queue flushes, and republishes through the above subjects.

### Caching

| Resource | TTL | Rationale |
|---|---|---|
| Problem catalog | 10 minutes | Updated infrequently by Codeforces |
| Rating history | 60 minutes | Staleness banner shown after expiry |
| Contest submissions | 30 seconds | Verdict status changes during judging |
| User profile | On-demand | Refreshed explicitly or on WebSocket event |

SwiftData provides a persistent backing store for `PersistedProblem`, `PersistedRatingChange`, and `PersistedContest`. On first launch or cache miss, data is fetched from the API; on subsequent launches within TTL, the local store is used, thereby making the app functional with no network.

### On-device ML

The `RecommendationEngine` runs entirely on the device using Core ML. It bypasses the network stack completely, thus having no inference API and transmitting no user data.

At runtime, `RecommendationViewModel` fetches the problem catalog and the user's submission history concurrently, then calls `RecommendationEngine.recommend()` which:

1. Builds a solved-problem key set from accepted submissions
2. Computes per-tag success rates from the full history
3. Constructs an 80-feature `MLDictionaryFeatureProvider` per unsolved problem
4. Runs `ProblemRecommender1` (Random Forest, 100 trees) via `MLModel.prediction(from:)`
5. Sorts by `P(recommended=1)` and returns the top 20

`MLDictionaryFeatureProvider` is used instead of the auto-generated `ProblemRecommender1Input` struct because one CF tag (`*special`) contains a character that is not a valid Swift identifier, which breaks the Xcode-generated input class.

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Swift 5.9 |
| UI | SwiftUI |
| ML | Core ML · Create ML · Random Forest |
| Concurrency | async/await · Actor model |
| Real-time | WebSocket (`URLSessionWebSocketTask`) |
| Persistence | SwiftData |
| Image Loading | SDWebImage |
| Code Quality | SwiftLint |
| API | Codeforces REST API |

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/Sandesh282/CForge.git
   cd CForge
   ```
2. Open in Xcode:
   ```bash
   open CForge.xcodeproj
   ```
3. Go to **Signing & Capabilities**, select your team, and update the bundle identifier if needed.
4. Run on a simulator or connected iOS device (iOS 17+).

## API Endpoints

| Endpoint | Usage |
|---|---|
| `contest.list` | Upcoming and running contests |
| `user.info` | Profile, rating, and rank |
| `user.status` | Full submission history for recommendations |
| `user.rating` | Rating change history for the chart |
| `problemset.problems` | Full problem catalog with tags and ratings |
