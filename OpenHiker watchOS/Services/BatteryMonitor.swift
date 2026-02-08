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
import WatchKit
import Combine

/// Monitors the Apple Watch battery level and publishes low-battery state.
///
/// During active hike tracking, this service polls the battery level at a
/// configurable interval (default: 60 seconds). When the battery level drops
/// to or below ``criticalBatteryThreshold`` (5%), it publishes
/// ``isLowBatteryMode`` = `true` and posts a ``Notification.Name.lowBatteryTriggered``
/// notification so views and services can react (e.g., save track state, switch
/// to minimal UI, reduce GPS accuracy).
///
/// ## Usage
/// Inject as an `@EnvironmentObject` from the app entry point. Call
/// ``startMonitoring()`` when tracking begins, and ``stopMonitoring()``
/// when tracking ends.
///
/// ## Battery API
/// Uses `WKInterfaceDevice.current().batteryLevel` (0.0–1.0) and
/// `isBatteryMonitoringEnabled`. watchOS does not provide battery-level
/// change notifications, so polling is required.
final class BatteryMonitor: ObservableObject {

    // MARK: - Configuration

    /// Battery level at or below which the app enters low-battery mode.
    ///
    /// 0.05 corresponds to 5%. When reached during active tracking, the app
    /// saves track state and switches to a minimal battery-saving UI.
    static let criticalBatteryThreshold: Float = 0.05

    /// How often (in seconds) the battery level is polled during active tracking.
    ///
    /// 60 seconds provides a good balance between responsiveness and efficiency.
    /// Battery level changes slowly, so more frequent polling is unnecessary.
    static let pollingIntervalSec: TimeInterval = 60.0

    // MARK: - Published Properties

    /// Whether the watch has entered low-battery mode (battery <= 5%).
    ///
    /// Once set to `true`, remains `true` for the rest of the tracking session.
    /// The UI should switch to ``LowBatteryTrackingView`` when this is `true`.
    @Published private(set) var isLowBatteryMode = false

    /// The current battery level as a percentage (0–100), or `nil` if unknown.
    ///
    /// Updated every ``pollingIntervalSec`` seconds while monitoring is active.
    @Published private(set) var batteryPercentage: Int?

    // MARK: - Internal State

    /// Timer that fires periodically to check the battery level.
    private var pollingTimer: Timer?

    /// Whether battery monitoring is currently active.
    private var isMonitoring = false

    // MARK: - Initialization

    /// Creates a new BatteryMonitor.
    ///
    /// Does not start monitoring automatically — call ``startMonitoring()``
    /// when tracking begins.
    init() {}

    // MARK: - Public Methods

    /// Starts periodic battery level polling.
    ///
    /// Enables `WKInterfaceDevice` battery monitoring and begins polling
    /// every ``pollingIntervalSec`` seconds. Safe to call multiple times —
    /// subsequent calls are no-ops if already monitoring.
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true

        // Check immediately on start
        checkBatteryLevel()

        // Schedule periodic checks
        pollingTimer = Timer.scheduledTimer(
            withTimeInterval: Self.pollingIntervalSec,
            repeats: true
        ) { [weak self] _ in
            self?.checkBatteryLevel()
        }

        print("BatteryMonitor: started monitoring (interval: \(Self.pollingIntervalSec)s)")
    }

    /// Stops periodic battery level polling.
    ///
    /// Invalidates the polling timer and disables device battery monitoring.
    /// Does not reset ``isLowBatteryMode`` — once triggered, it stays `true`
    /// until the next tracking session starts.
    func stopMonitoring() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        isMonitoring = false

        WKInterfaceDevice.current().isBatteryMonitoringEnabled = false
        print("BatteryMonitor: stopped monitoring")
    }

    /// Resets the low-battery mode flag for a new tracking session.
    ///
    /// Call this when starting a new track to clear any previous
    /// low-battery state from a prior session.
    func reset() {
        isLowBatteryMode = false
        batteryPercentage = nil
    }

    // MARK: - Private Methods

    /// Reads the current battery level and triggers low-battery mode if critical.
    ///
    /// Called by the polling timer and once on ``startMonitoring()``.
    /// Updates ``batteryPercentage`` and, if the level is at or below
    /// ``criticalBatteryThreshold``, sets ``isLowBatteryMode`` to `true`
    /// and posts a notification.
    private func checkBatteryLevel() {
        let device = WKInterfaceDevice.current()
        let level = device.batteryLevel

        // batteryLevel returns -1.0 if monitoring is disabled or unavailable
        guard level >= 0 else { return }

        let percentage = Int(level * 100)
        batteryPercentage = percentage

        if level <= Self.criticalBatteryThreshold && !isLowBatteryMode {
            isLowBatteryMode = true
            NotificationCenter.default.post(
                name: .lowBatteryTriggered,
                object: nil,
                userInfo: ["batteryLevel": percentage]
            )
            print("BatteryMonitor: LOW BATTERY (\(percentage)%) — entering low-battery mode")
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when the battery level drops to or below the critical threshold during tracking.
    ///
    /// The `userInfo` dictionary contains `"batteryLevel"` (Int) with the current
    /// percentage. Subscribers should save track state and switch to minimal UI.
    static let lowBatteryTriggered = Notification.Name("lowBatteryTriggered")
}
