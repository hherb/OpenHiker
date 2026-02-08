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
import os

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
@MainActor
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

    /// Number of consecutive unavailable (-1.0) readings before logging a warning.
    ///
    /// If the battery API consistently returns -1.0, the monitor logs a warning
    /// after this many consecutive failures so developers can diagnose the issue.
    private static let unavailableReadingWarningThreshold = 3

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

    // MARK: - Callback

    /// Closure invoked on the main actor when low-battery mode is first triggered.
    ///
    /// Set by the view layer to perform emergency saves before the UI swaps.
    /// This avoids the race condition where NotificationCenter-based handlers
    /// on views may not fire if the view is removed from the hierarchy first.
    var onLowBatteryTriggered: (() -> Void)?

    // MARK: - Internal State

    /// Timer that fires periodically to check the battery level.
    private var pollingTimer: Timer?

    /// Whether battery monitoring is currently active.
    private var isMonitoring = false

    /// Number of consecutive times `batteryLevel` returned -1.0.
    private var consecutiveUnavailableReadings = 0

    /// Logger for battery monitoring events.
    private static let logger = Logger(
        subsystem: "com.openhiker.watchos",
        category: "BatteryMonitor"
    )

    // MARK: - Initialization

    /// Creates a new BatteryMonitor.
    ///
    /// Does not start monitoring automatically — call ``startMonitoring()``
    /// when tracking begins.
    init() {}

    deinit {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    // MARK: - Public Methods

    /// Starts periodic battery level polling.
    ///
    /// Enables `WKInterfaceDevice` battery monitoring and begins polling
    /// every ``pollingIntervalSec`` seconds. Safe to call multiple times —
    /// subsequent calls are no-ops if already monitoring.
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        consecutiveUnavailableReadings = 0

        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true

        // Verify battery monitoring is working
        let initialLevel = device.batteryLevel
        if initialLevel < 0 {
            Self.logger.warning("Battery monitoring enabled but batteryLevel returned -1.0 — API may be unavailable on this device")
        }

        // Check immediately on start
        checkBatteryLevel()

        // Schedule periodic checks
        pollingTimer = Timer.scheduledTimer(
            withTimeInterval: Self.pollingIntervalSec,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkBatteryLevel()
            }
        }

        Self.logger.info("Started monitoring (interval: \(Self.pollingIntervalSec)s)")
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
        consecutiveUnavailableReadings = 0

        WKInterfaceDevice.current().isBatteryMonitoringEnabled = false
        Self.logger.info("Stopped monitoring")
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
    /// ``criticalBatteryThreshold``, sets ``isLowBatteryMode`` to `true`,
    /// invokes the ``onLowBatteryTriggered`` callback, and posts a notification.
    private func checkBatteryLevel() {
        let device = WKInterfaceDevice.current()
        let level = device.batteryLevel

        // batteryLevel returns -1.0 if monitoring is disabled or unavailable
        guard level >= 0 else {
            consecutiveUnavailableReadings += 1
            if consecutiveUnavailableReadings == Self.unavailableReadingWarningThreshold {
                Self.logger.warning("Battery level unavailable for \(self.consecutiveUnavailableReadings) consecutive readings — low-battery protection may not work")
            }
            return
        }

        consecutiveUnavailableReadings = 0
        let percentage = Int(level * 100)
        batteryPercentage = percentage

        if level <= Self.criticalBatteryThreshold && !isLowBatteryMode {
            isLowBatteryMode = true

            // Invoke callback first (before notification) so emergency save
            // happens while views are still mounted
            onLowBatteryTriggered?()

            NotificationCenter.default.post(
                name: .lowBatteryTriggered,
                object: nil,
                userInfo: ["batteryLevel": percentage]
            )
            Self.logger.warning("LOW BATTERY (\(percentage)%) — entering low-battery mode")
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
