// Copyright (C) 2024-2026 Dr Horst Herb
//
// This file is part of OpenHiker.
//
// OpenHiker is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// OpenHiker is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with OpenHiker. If not, see <https://www.gnu.org/licenses/>.

import Foundation
import WeatherKit
import CoreLocation
import Combine

/// Manages real-time UV index data for the watchOS app using Apple WeatherKit.
///
/// This service fetches the current UV index based on the user's GPS location
/// and publishes it for display in overlays and the hike stats view. It uses
/// the Apple Weather service (WeatherKit) which provides location-based UV index
/// data — no on-device UV sensor is required.
///
/// ## Update Strategy
/// - Fetches UV index when a location update is received
/// - Rate-limits requests to at most once per ``UVIndexConfig/refreshIntervalSec``
/// - Retries failed requests with exponential backoff (up to ``UVIndexConfig/maxRetries`` attempts)
///
/// ## Graceful Degradation
/// If WeatherKit is unavailable (missing entitlement, network error, or user denied
/// location), ``currentUVIndex`` remains `nil` and the UI simply hides the UV badge.
final class UVIndexManager: ObservableObject {

    // MARK: - Published Properties

    /// The most recent UV index value (0-11+), or `nil` if not yet fetched.
    @Published private(set) var currentUVIndex: Int?

    /// The UV exposure category for the current reading.
    @Published private(set) var currentCategory: UVCategory?

    /// Whether a fetch is currently in progress.
    @Published private(set) var isFetching = false

    /// The most recent error from a WeatherKit fetch, or `nil` if the last fetch succeeded.
    @Published private(set) var fetchError: Error?

    // MARK: - Internal State

    /// The WeatherKit service instance used for all weather data requests.
    private let weatherService = WeatherService()

    /// Timestamp of the last successful UV index fetch, used for rate-limiting.
    private var lastFetchDate: Date?

    /// Number of consecutive fetch failures, used for exponential backoff.
    private var consecutiveFailures = 0

    // MARK: - Public Methods

    /// Updates the UV index for the given location.
    ///
    /// Rate-limits requests to avoid excessive WeatherKit API calls. If a fetch
    /// was performed less than ``UVIndexConfig/refreshIntervalSec`` ago, the
    /// request is silently ignored.
    ///
    /// - Parameter location: The user's current GPS location.
    func updateUVIndex(for location: CLLocation) {
        guard shouldFetch() else { return }

        Task {
            await fetchUVIndex(for: location)
        }
    }

    /// Forces an immediate UV index fetch regardless of the rate limit.
    ///
    /// Use this when the user explicitly requests a refresh or when the app
    /// first launches with a known location.
    ///
    /// - Parameter location: The user's current GPS location.
    func forceUpdate(for location: CLLocation) {
        Task {
            await fetchUVIndex(for: location)
        }
    }

    // MARK: - Private Methods

    /// Determines whether enough time has elapsed since the last fetch.
    ///
    /// Also applies exponential backoff after consecutive failures:
    /// base interval * 2^(failure count), capped at 10 minutes.
    ///
    /// - Returns: `true` if a new fetch should be performed.
    private func shouldFetch() -> Bool {
        guard let lastFetch = lastFetchDate else { return true }

        let baseInterval = UVIndexConfig.refreshIntervalSec
        let backoffMultiplier = pow(2.0, Double(min(consecutiveFailures, UVIndexConfig.maxRetries)))
        let effectiveInterval = min(baseInterval * backoffMultiplier, UVIndexConfig.maxBackoffSec)

        return Date().timeIntervalSince(lastFetch) >= effectiveInterval
    }

    /// Fetches the current UV index from WeatherKit for the given location.
    ///
    /// Updates published properties on the main thread. On success, resets the
    /// failure counter. On failure, increments it for exponential backoff.
    ///
    /// - Parameter location: The GPS location to fetch weather data for.
    @MainActor
    private func fetchUVIndex(for location: CLLocation) async {
        isFetching = true
        defer { isFetching = false }

        do {
            let currentWeather = try await weatherService.weather(
                for: location,
                including: .current
            )

            let uvValue = currentWeather.uvIndex.value
            let category = UVCategory.from(index: uvValue)

            currentUVIndex = uvValue
            currentCategory = category
            fetchError = nil
            lastFetchDate = Date()
            consecutiveFailures = 0

        } catch {
            print("WeatherKit UV index fetch error: \(error.localizedDescription)")
            fetchError = error
            lastFetchDate = Date()
            consecutiveFailures = min(consecutiveFailures + 1, UVIndexConfig.maxRetries)
        }
    }
}

// MARK: - UV Category

/// Categorizes UV index values per the WHO/WMO standard scale.
///
/// Used to determine display color and protection advice text.
/// Categories follow the internationally recognized UV index scale:
/// - Low (0-2): No protection required
/// - Moderate (3-5): Protection recommended
/// - High (6-7): Protection essential
/// - Very High (8-10): Extra protection essential
/// - Extreme (11+): Stay indoors if possible
enum UVCategory: String, Equatable {
    case low = "Low"
    case moderate = "Moderate"
    case high = "High"
    case veryHigh = "Very High"
    case extreme = "Extreme"

    /// Maps a numeric UV index to its WHO/WMO category.
    ///
    /// - Parameter index: The UV index value (0-11+).
    /// - Returns: The corresponding ``UVCategory``.
    static func from(index: Int) -> UVCategory {
        switch index {
        case 0...2:
            return .low
        case 3...5:
            return .moderate
        case 6...7:
            return .high
        case 8...10:
            return .veryHigh
        default:
            return .extreme
        }
    }

    /// The recommended display color for this UV category.
    ///
    /// Colors follow the standard WHO UV index color scheme:
    /// - Low: Green
    /// - Moderate: Yellow
    /// - High: Orange
    /// - Very High: Red
    /// - Extreme: Violet/Purple
    var displayColorName: String {
        switch self {
        case .low: return "green"
        case .moderate: return "yellow"
        case .high: return "orange"
        case .veryHigh: return "red"
        case .extreme: return "purple"
        }
    }

    /// A brief sun protection recommendation for this UV category.
    var protectionAdvice: String {
        switch self {
        case .low:
            return "No protection needed"
        case .moderate:
            return "Wear sunscreen"
        case .high:
            return "Reduce sun exposure"
        case .veryHigh:
            return "Avoid midday sun"
        case .extreme:
            return "Stay in shade"
        }
    }
}

// MARK: - Configuration

/// Configuration constants for UV index fetching and display.
///
/// These constants control how frequently the UV index is updated and
/// how the system handles failures. Defined as static constants rather
/// than magic numbers.
enum UVIndexConfig {

    /// Minimum interval between UV index fetches in seconds.
    ///
    /// 10 minutes balances freshness against WeatherKit API quota
    /// (500,000 calls/month free tier). UV index changes slowly —
    /// 10-minute resolution is more than adequate.
    static let refreshIntervalSec: TimeInterval = 600.0

    /// Maximum number of consecutive fetch retries before backing off fully.
    static let maxRetries: Int = 4

    /// Maximum backoff interval in seconds (10 minutes).
    static let maxBackoffSec: TimeInterval = 600.0

    /// Maximum age in seconds for a UV reading to be considered current.
    ///
    /// Readings older than 30 minutes are hidden from the overlay since
    /// the UV index may have changed significantly.
    static let maxReadingAgeSec: TimeInterval = 1800.0
}
