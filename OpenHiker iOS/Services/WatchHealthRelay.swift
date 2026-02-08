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
///
/// ## Heart Rate Averaging
/// When ``isReceivingData`` is `true`, incoming heart rate readings are
/// accumulated so that ``averageHeartRate`` can be stored alongside saved routes.
@MainActor
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

    /// Running sum of heart rate readings for computing the average.
    private var heartRateSum: Double = 0

    /// Number of heart rate readings received for computing the average.
    private var heartRateCount: Int = 0

    // MARK: - Computed Properties

    /// The running average heart rate across all readings in this session, or `nil`
    /// if no heart rate data has been received.
    var averageHeartRate: Double? {
        guard heartRateCount > 0 else { return nil }
        return heartRateSum / Double(heartRateCount)
    }

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
    func update(heartRate: Double?, spO2: Double?, uvIndex: Int?) {
        let now = Date()

        if let hr = heartRate {
            self.heartRate = hr
            self.heartRateTimestamp = now
            self.heartRateSum += hr
            self.heartRateCount += 1
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
    func clearAll() {
        heartRate = nil
        spO2 = nil
        uvIndex = nil
        uvCategory = nil
        isReceivingData = false
        heartRateTimestamp = nil
        spO2Timestamp = nil
        uvIndexTimestamp = nil
        heartRateSum = 0
        heartRateCount = 0
    }

    // MARK: - Staleness Timer

    /// Starts a repeating timer that clears stale readings.
    ///
    /// The timer fires on the main RunLoop because the class is `@MainActor`.
    private func startStalenessTimer() {
        stalenessTimer = Timer.scheduledTimer(
            withTimeInterval: Self.stalenessCheckIntervalSec,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkStaleness()
            }
        }
    }

    /// Clears any readings that are older than ``maxReadingAgeSec``.
    private func checkStaleness() {
        let now = Date()

        if let ts = heartRateTimestamp, now.timeIntervalSince(ts) > Self.maxReadingAgeSec {
            heartRate = nil
            heartRateTimestamp = nil
        }

        if let ts = spO2Timestamp, now.timeIntervalSince(ts) > Self.maxReadingAgeSec {
            spO2 = nil
            spO2Timestamp = nil
        }

        if let ts = uvIndexTimestamp, now.timeIntervalSince(ts) > Self.maxReadingAgeSec {
            uvIndex = nil
            uvCategory = nil
            uvIndexTimestamp = nil
        }

        // If all readings are nil, we're no longer actively receiving
        if heartRate == nil && spO2 == nil && uvIndex == nil {
            isReceivingData = false
        }
    }
}
