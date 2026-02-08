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
import Combine
import SwiftUI

// MARK: - UV Category

/// WHO/WMO UV index exposure categories with associated colours.
///
/// Duplicated from the watchOS ``UVIndexManager`` so the iPhone can display
/// UV categories without depending on WeatherKit.
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
        case 0...2: return .low
        case 3...5: return .moderate
        case 6...7: return .high
        case 8...10: return .veryHigh
        default: return .extreme
        }
    }

    /// The recommended display color for this UV category.
    ///
    /// Colors follow the standard WHO UV index color scheme.
    var displayColor: Color {
        switch self {
        case .low: return .green
        case .moderate: return .yellow
        case .high: return .orange
        case .veryHigh: return .red
        case .extreme: return .purple
        }
    }
}

/// Receives live health and environmental data relayed from the Apple Watch
/// via WatchConnectivity and publishes it for display on the iPhone navigation UI.
///
/// The paired watch sends periodic updates containing heart rate, SpO2, and UV
/// index whenever a workout or hike is active. This class stores the latest values
/// and exposes them as `@Published` properties for SwiftUI binding.
///
/// ## Data Flow
/// 1. Watch ``HealthKitManager`` collects heart rate and SpO2 from HealthKit
/// 2. Watch ``UVIndexManager`` fetches UV index from WeatherKit
/// 3. Watch ``WatchConnectivityReceiver`` sends a `"healthUpdate"` message
///    via `WCSession.sendMessage()`
/// 4. iPhone ``WatchConnectivityManager`` receives the message and calls
///    ``update(heartRate:spO2:uvIndex:)``
/// 5. iPhone ``iOSHikeStatsBar`` displays the values
///
/// ## Staleness
/// Each value has a timestamp. Values older than ``maxReadingAgeSec`` are
/// automatically cleared by a periodic timer to avoid displaying stale data.
final class WatchHealthRelay: ObservableObject {

    // MARK: - Published Properties

    /// The most recent heart rate in beats per minute, or `nil` if unavailable.
    @Published private(set) var heartRate: Double?

    /// The most recent SpO2 as a fraction (0.0-1.0), or `nil` if unavailable.
    @Published private(set) var spO2: Double?

    /// The most recent UV index (0-11+), or `nil` if unavailable.
    @Published private(set) var uvIndex: Int?

    /// The UV exposure category for the current reading, or `nil` if unavailable.
    @Published private(set) var uvCategory: UVCategory?

    /// Whether the watch is actively sending health data (workout in progress).
    @Published private(set) var isReceivingData: Bool = false

    // MARK: - Configuration

    /// Maximum age in seconds for a health reading to be considered current.
    ///
    /// Readings older than this are cleared. SpO2 and UV readings may be
    /// less frequent than heart rate, so this is generous.
    static let maxReadingAgeSec: TimeInterval = 120.0

    /// Interval for checking reading freshness.
    private static let stalenessCheckIntervalSec: TimeInterval = 30.0

    // MARK: - Internal State

    /// Timestamp of the last heart rate update.
    private var heartRateTimestamp: Date?

    /// Timestamp of the last SpO2 update.
    private var spO2Timestamp: Date?

    /// Timestamp of the last UV index update.
    private var uvIndexTimestamp: Date?

    /// Timer that periodically checks for stale readings.
    private var stalenessTimer: Timer?

    // MARK: - Initialization

    /// Creates a new health relay and starts the staleness timer.
    init() {
        startStalenessTimer()
    }

    deinit {
        stalenessTimer?.invalidate()
    }

    // MARK: - Public API

    /// Updates all health values from a watch message.
    ///
    /// Called by ``WatchConnectivityManager`` when a `"healthUpdate"` message
    /// arrives from the watch.
    ///
    /// - Parameters:
    ///   - heartRate: Heart rate in BPM, or `nil` if not available.
    ///   - spO2: Blood oxygen saturation as a fraction (0.0-1.0), or `nil`.
    ///   - uvIndex: UV index value (0-11+), or `nil`.
    @MainActor
    func update(heartRate: Double?, spO2: Double?, uvIndex: Int?) {
        let now = Date()

        if let hr = heartRate {
            self.heartRate = hr
            self.heartRateTimestamp = now
        }

        if let spo2 = spO2 {
            self.spO2 = spo2
            self.spO2Timestamp = now
        }

        if let uv = uvIndex {
            self.uvIndex = uv
            self.uvCategory = UVCategory.from(index: uv)
            self.uvIndexTimestamp = now
        }

        self.isReceivingData = true
    }

    /// Clears all health data, typically when the watch workout ends.
    @MainActor
    func clearAll() {
        heartRate = nil
        spO2 = nil
        uvIndex = nil
        uvCategory = nil
        isReceivingData = false
        heartRateTimestamp = nil
        spO2Timestamp = nil
        uvIndexTimestamp = nil
    }

    // MARK: - Staleness Timer

    /// Starts a repeating timer that clears stale readings.
    private func startStalenessTimer() {
        stalenessTimer = Timer.scheduledTimer(
            withTimeInterval: Self.stalenessCheckIntervalSec,
            repeats: true
        ) { [weak self] _ in
            self?.checkStaleness()
        }
    }

    /// Clears any readings that are older than ``maxReadingAgeSec``.
    private func checkStaleness() {
        let now = Date()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if let ts = self.heartRateTimestamp, now.timeIntervalSince(ts) > Self.maxReadingAgeSec {
                self.heartRate = nil
                self.heartRateTimestamp = nil
            }

            if let ts = self.spO2Timestamp, now.timeIntervalSince(ts) > Self.maxReadingAgeSec {
                self.spO2 = nil
                self.spO2Timestamp = nil
            }

            if let ts = self.uvIndexTimestamp, now.timeIntervalSince(ts) > Self.maxReadingAgeSec {
                self.uvIndex = nil
                self.uvCategory = nil
                self.uvIndexTimestamp = nil
            }

            // If all readings are nil, we're no longer actively receiving
            if self.heartRate == nil && self.spO2 == nil && self.uvIndex == nil {
                self.isReceivingData = false
            }
        }
    }
}
