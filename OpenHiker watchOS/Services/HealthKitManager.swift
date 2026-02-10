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
import HealthKit
import CoreLocation
import Combine

/// Manages HealthKit integration for the watchOS hiking app.
///
/// This class provides three capabilities:
/// 1. **Live vitals**: Real-time heart rate and SpO2 readings via `HKAnchoredObjectQuery`
/// 2. **Workout recording**: Start/stop `HKWorkoutSession` that keeps the app running
///    in the background and records the hike as an `HKWorkout`
/// 3. **Route tracking**: Feeds GPS locations to `HKWorkoutRouteBuilder` so the workout
///    appears with a GPS route in Apple Health
///
/// ## Thread Safety
/// `HKHealthStore` is thread-safe, so this class is a standard `ObservableObject`
/// rather than a Swift Actor. Published properties are always updated on the main thread.
///
/// ## Graceful Degradation
/// If HealthKit is unavailable (e.g. older devices, MDM restrictions) or the user
/// denies authorization, all methods become no-ops and the stats overlay simply
/// hides the vitals section. Tracking continues to work without HealthKit.
final class HealthKitManager: NSObject, ObservableObject, @unchecked Sendable {

    // MARK: - Published Properties

    /// The most recent heart rate reading in beats per minute, or `nil` if unavailable.
    @Published private(set) var currentHeartRate: Double?

    /// The most recent blood oxygen saturation as a fraction (0.0-1.0), or `nil` if unavailable.
    ///
    /// Only set when the reading is less than ``HikeStatisticsConfig/spO2MaxAgeSec`` old.
    @Published private(set) var currentSpO2: Double?

    /// Whether the user has granted HealthKit authorization for the required data types.
    @Published private(set) var isAuthorized = false

    /// Whether an HKWorkoutSession is currently running.
    @Published private(set) var workoutActive = false

    /// Any error encountered during HealthKit operations, for display in the UI.
    @Published private(set) var healthKitError: Error?

    // MARK: - Internal State

    /// The shared HealthKit store. `nil` if HealthKit is not available on this device.
    private var healthStore: HKHealthStore?

    /// The active workout session, or `nil` when no workout is running.
    private var workoutSession: HKWorkoutSession?

    /// The live workout builder that collects samples during the workout.
    private var workoutBuilder: HKLiveWorkoutBuilder?

    /// The route builder that aggregates GPS locations for the workout route.
    private var routeBuilder: HKWorkoutRouteBuilder?

    /// The anchored query for live heart rate updates.
    private var heartRateQuery: HKAnchoredObjectQuery?

    /// The anchored query for SpO2 updates.
    private var spO2Query: HKAnchoredObjectQuery?

    /// Serial queue protecting ``heartRateSamples`` and ``spO2Samples`` from
    /// concurrent access across HealthKit background callbacks and the main thread.
    private let samplesQueue = DispatchQueue(label: "com.openhiker.samples", qos: .userInitiated)

    /// All heart rate samples collected during the current workout, used for avg/max calculations.
    ///
    /// - Important: Always access via ``samplesQueue`` to avoid data races.
    private var heartRateSamples: [Double] = []

    /// All SpO2 samples collected during the current workout, used for average calculations.
    ///
    /// - Important: Always access via ``samplesQueue`` to avoid data races.
    private var spO2Samples: [Double] = []

    /// The user's body mass in kg, read from HealthKit for calorie estimation.
    private var bodyMassKg: Double?

    /// The timestamp when the current workout started.
    private var workoutStartDate: Date?

    // MARK: - HealthKit Types

    /// The set of HealthKit data types we request read access for.
    private static let readTypes: Set<HKObjectType> = {
        var types = Set<HKObjectType>()
        if let hr = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            types.insert(hr)
        }
        if let spO2 = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) {
            types.insert(spO2)
        }
        if let mass = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            types.insert(mass)
        }
        return types
    }()

    /// The set of HealthKit data types we request write access for.
    ///
    /// Includes `HKSeriesType.workoutRoute()` for saving GPS routes with workouts.
    /// `HKSeriesType` is a subclass of `HKSampleType`, so no cast is needed.
    private static let writeTypes: Set<HKSampleType> = [
        HKWorkoutType.workoutType(),
        HKSeriesType.workoutRoute()
    ]

    // MARK: - Initialization

    /// Initializes the HealthKit manager.
    ///
    /// Checks if HealthKit is available on the current device. If not, the manager
    /// operates in a degraded mode where all methods are safe no-ops.
    override init() {
        super.init()

        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit is not available on this device")
            return
        }

        healthStore = HKHealthStore()
    }

    // MARK: - Authorization

    /// Requests HealthKit authorization for the required data types.
    ///
    /// Presents the system authorization dialog to the user. After authorization
    /// completes (whether granted or denied), updates ``isAuthorized`` and attempts
    /// to read the user's body mass for calorie estimation.
    ///
    /// - Throws: ``HealthKitError/notAvailable`` if HealthKit is not available,
    ///   or re-throws any HealthKit authorization error.
    func requestAuthorization() async throws {
        guard let healthStore = healthStore else {
            throw HealthKitError.notAvailable
        }

        do {
            try await healthStore.requestAuthorization(
                toShare: Self.writeTypes,
                read: Self.readTypes
            )

            // Check authorization status for workout type (a share type).
            // Note: authorizationStatus(for:) only reports *share* status.
            // Read-only types (heart rate, SpO2) don't expose their status
            // for privacy reasons — HealthKit returns empty results instead.
            let workoutStatus = healthStore.authorizationStatus(for: HKWorkoutType.workoutType())

            await MainActor.run {
                self.isAuthorized = (workoutStatus == .sharingAuthorized)
            }

            // Try to read body mass for calorie estimation
            await readBodyMass()

            print("HealthKit authorization completed. Authorized: \(isAuthorized)")
        } catch {
            print("HealthKit authorization error: \(error.localizedDescription)")
            await MainActor.run {
                self.healthKitError = error
            }
            throw error
        }
    }

    // MARK: - Workout Session

    /// Starts a HealthKit workout session for hiking.
    ///
    /// This creates an `HKWorkoutSession` with `.hiking` activity type, which provides:
    /// - Extended background runtime (app stays active on wrist-down)
    /// - Automatic heart rate monitoring
    /// - Workout recording in Apple Health
    ///
    /// Call this when the user taps "Start Tracking". If HealthKit is not available
    /// or not authorized, this method does nothing (graceful degradation).
    func startWorkout() {
        guard let healthStore = healthStore else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .hiking
        configuration.locationType = .outdoor

        do {
            workoutSession = try HKWorkoutSession(
                healthStore: healthStore,
                configuration: configuration
            )
            workoutBuilder = workoutSession?.associatedWorkoutBuilder()
            workoutBuilder?.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )

            workoutSession?.delegate = self
            workoutBuilder?.delegate = self

            routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)

            workoutStartDate = Date()
            samplesQueue.sync {
                heartRateSamples.removeAll()
                spO2Samples.removeAll()
            }

            workoutSession?.startActivity(with: workoutStartDate!)
            workoutBuilder?.beginCollection(withStart: workoutStartDate!) { success, error in
                if let error = error {
                    print("Error beginning workout collection: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.healthKitError = error
                    }
                }
            }

            setupHeartRateQuery()
            setupSpO2Query()

            DispatchQueue.main.async {
                self.workoutActive = true
            }

            print("HealthKit workout session started")
        } catch {
            print("Error starting workout session: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.healthKitError = error
            }
        }
    }

    /// Stops the current workout session and saves it to Apple Health.
    ///
    /// This ends the workout, saves all collected data (distance, calories, route),
    /// and returns the completed `HKWorkout` object.
    ///
    /// - Parameters:
    ///   - totalDistance: Final total distance from ``LocationManager/totalDistance``, in meters.
    ///   - elevationGain: Final elevation gain from ``LocationManager/elevationGain``, in meters.
    /// - Returns: The saved `HKWorkout`, or `nil` if HealthKit was not active.
    @discardableResult
    func stopWorkout(totalDistance: Double, elevationGain: Double) async -> HKWorkout? {
        guard let workoutSession = workoutSession,
              let workoutBuilder = workoutBuilder,
              let startDate = workoutStartDate else {
            print("stopWorkout() called but no active workout session exists")
            await MainActor.run {
                self.healthKitError = HealthKitError.workoutSaveFailed(
                    underlying: NSError(
                        domain: "HealthKitManager",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "No active workout to save."]
                    )
                )
            }
            return nil
        }

        let endDate = Date()
        workoutSession.end()

        // Stop heart rate and SpO2 queries
        stopQueries()

        // Calculate calories
        let durationSeconds = endDate.timeIntervalSince(startDate)
        let calories = CalorieEstimator.estimateCalories(
            distanceMeters: totalDistance,
            elevationGainMeters: elevationGain,
            durationSeconds: durationSeconds,
            bodyMassKg: bodyMassKg
        )

        // Add final distance and calorie samples
        let distanceQuantity = HKQuantity(unit: .meter(), doubleValue: totalDistance)
        let distanceSample = HKQuantitySample(
            type: HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            quantity: distanceQuantity,
            start: startDate,
            end: endDate
        )

        let calorieQuantity = HKQuantity(unit: .kilocalorie(), doubleValue: calories)
        let calorieSample = HKQuantitySample(
            type: HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            quantity: calorieQuantity,
            start: startDate,
            end: endDate
        )

        do {
            try await workoutBuilder.addSamples([distanceSample, calorieSample])
        } catch {
            print("Error adding final workout samples: \(error.localizedDescription)")
            await MainActor.run {
                self.healthKitError = error
            }
        }

        // End collection and save
        do {
            try await workoutBuilder.endCollection(at: endDate)
            let savedWorkout = try await workoutBuilder.finishWorkout()

            // Finish route if we have location data
            if let routeBuilder = routeBuilder, let workout = savedWorkout {
                try await routeBuilder.finishRoute(with: workout, metadata: nil)
            }

            await MainActor.run {
                self.workoutActive = false
                self.currentHeartRate = nil
                self.currentSpO2 = nil
            }

            print("HealthKit workout saved successfully")

            // Clean up references
            self.workoutSession = nil
            self.workoutBuilder = nil
            self.routeBuilder = nil
            self.workoutStartDate = nil

            return savedWorkout
        } catch {
            print("Error finishing workout: \(error.localizedDescription)")
            await MainActor.run {
                self.healthKitError = error
                self.workoutActive = false
            }
            return nil
        }
    }

    /// Feeds GPS locations to the workout route builder.
    ///
    /// Call this whenever new GPS locations arrive from ``LocationManager``.
    /// The route builder aggregates these points and attaches them to the
    /// workout when it finishes, so the route appears on the Apple Health map.
    ///
    /// - Parameter locations: An array of `CLLocation` objects to add to the route.
    func addRoutePoints(_ locations: [CLLocation]) {
        guard let routeBuilder = routeBuilder, workoutActive else { return }

        routeBuilder.insertRouteData(locations) { [weak self] success, error in
            if let error = error {
                print("Error inserting route data: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.healthKitError = error
                }
            }
        }
    }

    // MARK: - Heart Rate Query

    /// Sets up an anchored object query for live heart rate samples.
    ///
    /// Uses `HKAnchoredObjectQuery` with an update handler that delivers new
    /// heart rate samples as they arrive from the Apple Watch sensors. Each new
    /// sample updates ``currentHeartRate`` on the main thread.
    private func setupHeartRateQuery() {
        guard let healthStore = healthStore else { return }

        let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let predicate = HKQuery.predicateForSamples(
            withStart: workoutStartDate,
            end: nil,
            options: .strictStartDate
        )

        let query = HKAnchoredObjectQuery(
            type: hrType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, error in
            if let error = error {
                print("Heart rate query error: \(error.localizedDescription)")
                DispatchQueue.main.async { self?.healthKitError = error }
                return
            }
            self?.processHeartRateSamples(samples)
        }

        query.updateHandler = { [weak self] _, samples, _, _, error in
            if let error = error {
                print("Heart rate update error: \(error.localizedDescription)")
                DispatchQueue.main.async { self?.healthKitError = error }
                return
            }
            self?.processHeartRateSamples(samples)
        }

        heartRateQuery = query
        healthStore.execute(query)
    }

    /// Processes new heart rate samples from the anchored query.
    ///
    /// Extracts the BPM value from each `HKQuantitySample`, stores it for
    /// aggregate calculations, and updates ``currentHeartRate`` with the
    /// most recent value.
    ///
    /// - Parameter samples: The new samples delivered by the query, or `nil`.
    private func processHeartRateSamples(_ samples: [HKSample]?) {
        guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else { return }

        let bpmUnit = HKUnit.count().unitDivided(by: .minute())

        let bpmValues = samples.map { $0.quantity.doubleValue(for: bpmUnit) }
        samplesQueue.sync {
            heartRateSamples.append(contentsOf: bpmValues)
        }

        if let latestBPM = bpmValues.last {
            DispatchQueue.main.async {
                self.currentHeartRate = latestBPM
            }
        }
    }

    // MARK: - SpO2 Query

    /// Sets up an anchored object query for blood oxygen saturation samples.
    ///
    /// SpO2 readings are intermittent (not continuous like heart rate), so this
    /// query may not deliver samples frequently. Each sample is timestamped and
    /// only displayed if it's less than ``HikeStatisticsConfig/spO2MaxAgeSec`` old.
    private func setupSpO2Query() {
        guard let healthStore = healthStore else { return }

        guard let spO2Type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) else {
            return
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: workoutStartDate,
            end: nil,
            options: .strictStartDate
        )

        let query = HKAnchoredObjectQuery(
            type: spO2Type,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, error in
            if let error = error {
                print("SpO2 query error: \(error.localizedDescription)")
                DispatchQueue.main.async { self?.healthKitError = error }
                return
            }
            self?.processSpO2Samples(samples)
        }

        query.updateHandler = { [weak self] _, samples, _, _, error in
            if let error = error {
                print("SpO2 update error: \(error.localizedDescription)")
                DispatchQueue.main.async { self?.healthKitError = error }
                return
            }
            self?.processSpO2Samples(samples)
        }

        spO2Query = query
        healthStore.execute(query)
    }

    /// Processes new SpO2 samples from the anchored query.
    ///
    /// Only updates ``currentSpO2`` if the most recent sample is less than
    /// ``HikeStatisticsConfig/spO2MaxAgeSec`` old. Older samples are discarded
    /// from the display (though still stored for average calculation).
    ///
    /// - Parameter samples: The new samples delivered by the query, or `nil`.
    private func processSpO2Samples(_ samples: [HKSample]?) {
        guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else { return }

        let percentUnit = HKUnit.percent()

        let spO2Values = samples.map { $0.quantity.doubleValue(for: percentUnit) }
        samplesQueue.sync {
            spO2Samples.append(contentsOf: spO2Values)
        }

        if let latestSample = samples.last {
            let age = Date().timeIntervalSince(latestSample.endDate)
            if age < HikeStatisticsConfig.spO2MaxAgeSec {
                let value = latestSample.quantity.doubleValue(for: percentUnit)
                DispatchQueue.main.async {
                    self.currentSpO2 = value
                }
            }
        }
    }

    /// Stops and removes the active heart rate and SpO2 queries.
    private func stopQueries() {
        if let heartRateQuery = heartRateQuery {
            healthStore?.stop(heartRateQuery)
            self.heartRateQuery = nil
        }
        if let spO2Query = spO2Query {
            healthStore?.stop(spO2Query)
            self.spO2Query = nil
        }
    }

    // MARK: - Body Mass

    /// Reads the user's most recent body mass from HealthKit for calorie estimation.
    ///
    /// Uses a sample query sorted by date descending, limited to 1 result.
    /// If no body mass data is available, ``CalorieEstimator`` falls back to
    /// ``HikeStatisticsConfig/defaultBodyMassKg`` (70 kg).
    private func readBodyMass() async {
        guard let healthStore = healthStore,
              let massType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            return
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let query = HKSampleQuery(
                sampleType: massType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { [weak self] _, results, error in
                if let error = error {
                    print("Error reading body mass: \(error.localizedDescription)")
                    // Non-fatal: CalorieEstimator falls back to defaultBodyMassKg
                } else if let sample = results?.first as? HKQuantitySample {
                    let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                    self?.bodyMassKg = kg
                    print("Read body mass from HealthKit: \(kg) kg")
                } else {
                    print("No body mass data in HealthKit, using default \(HikeStatisticsConfig.defaultBodyMassKg) kg")
                }
                continuation.resume()
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Statistics Snapshot

    /// Creates a snapshot of the current hike statistics.
    ///
    /// Combines data from ``LocationManager`` (distance, elevation, duration) with
    /// HealthKit vitals (heart rate, SpO2) into a single ``HikeStatistics`` value.
    /// This is used for saving completed hikes and generating reports.
    ///
    /// - Parameter locationManager: The location manager providing GPS-derived statistics.
    /// - Returns: A complete ``HikeStatistics`` snapshot.
    func createStatisticsSnapshot(from locationManager: LocationManager) -> HikeStatistics {
        let distance = locationManager.totalDistance
        let duration = locationManager.duration ?? 0
        let gain = locationManager.elevationGain
        let loss = locationManager.elevationLoss

        // Calculate walking vs resting time from track points
        let (walkingTime, restingTime) = calculateWalkingRestingTime(
            trackPoints: locationManager.trackPoints
        )

        // Heart rate and SpO2 aggregates — read under lock
        let (avgHR, maxHR, avgSpO2): (Double?, Double?, Double?) = samplesQueue.sync {
            let hr: Double? = heartRateSamples.isEmpty ? nil :
                heartRateSamples.reduce(0, +) / Double(heartRateSamples.count)
            let hrMax: Double? = heartRateSamples.isEmpty ? nil : heartRateSamples.max()
            let spo2: Double? = spO2Samples.isEmpty ? nil :
                spO2Samples.reduce(0, +) / Double(spO2Samples.count)
            return (hr, hrMax, spo2)
        }

        // Calorie estimation
        let calories = CalorieEstimator.estimateCalories(
            distanceMeters: distance,
            elevationGainMeters: gain,
            durationSeconds: duration,
            bodyMassKg: bodyMassKg
        )

        // Speed calculations
        let avgSpeed = duration > 0 ? distance / duration : 0
        let maxSpeed = calculateMaxSpeed(trackPoints: locationManager.trackPoints)

        return HikeStatistics(
            totalDistance: distance,
            elevationGain: gain,
            elevationLoss: loss,
            duration: duration,
            walkingTime: walkingTime,
            restingTime: restingTime,
            averageHeartRate: avgHR,
            maxHeartRate: maxHR,
            averageSpO2: avgSpO2,
            estimatedCalories: calories,
            averageSpeed: avgSpeed,
            maxSpeed: maxSpeed
        )
    }

    // MARK: - Speed & Time Calculations

    /// Calculates the split between walking time and resting time from GPS track points.
    ///
    /// A segment between two consecutive points is classified as "resting" if the
    /// speed between them is below ``HikeStatisticsConfig/restingSpeedThreshold``.
    ///
    /// - Parameter trackPoints: The recorded GPS locations from the hike.
    /// - Returns: A tuple of (walkingTime, restingTime) in seconds.
    private func calculateWalkingRestingTime(trackPoints: [CLLocation]) -> (TimeInterval, TimeInterval) {
        guard trackPoints.count > 1 else { return (0, 0) }

        var walking: TimeInterval = 0
        var resting: TimeInterval = 0

        for i in 1..<trackPoints.count {
            let distance = trackPoints[i].distance(from: trackPoints[i - 1])
            let timeDelta = trackPoints[i].timestamp.timeIntervalSince(trackPoints[i - 1].timestamp)

            guard timeDelta > 0 else { continue }

            let speed = distance / timeDelta
            if speed >= HikeStatisticsConfig.restingSpeedThreshold {
                walking += timeDelta
            } else {
                resting += timeDelta
            }
        }

        return (walking, resting)
    }

    /// Calculates the maximum speed from GPS track points.
    ///
    /// Iterates through consecutive point pairs and returns the highest instantaneous
    /// speed in meters per second.
    ///
    /// - Parameter trackPoints: The recorded GPS locations from the hike.
    /// - Returns: Maximum speed in m/s, or 0 if fewer than 2 points exist.
    private func calculateMaxSpeed(trackPoints: [CLLocation]) -> Double {
        guard trackPoints.count > 1 else { return 0 }

        var maxSpd: Double = 0
        for i in 1..<trackPoints.count {
            let distance = trackPoints[i].distance(from: trackPoints[i - 1])
            let timeDelta = trackPoints[i].timestamp.timeIntervalSince(trackPoints[i - 1].timestamp)

            guard timeDelta > 0 else { continue }

            let speed = distance / timeDelta
            maxSpd = max(maxSpd, speed)
        }

        return maxSpd
    }
}

// MARK: - HKWorkoutSessionDelegate

extension HealthKitManager: HKWorkoutSessionDelegate {
    /// Called when the workout session changes state.
    ///
    /// Logs state transitions. If the session ends unexpectedly (e.g. due to
    /// a system error), updates ``workoutActive`` accordingly.
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        print("Workout session state changed: \(fromState.rawValue) -> \(toState.rawValue)")

        if toState == .ended {
            DispatchQueue.main.async {
                self.workoutActive = false
            }
        }
    }

    /// Called when the workout session fails with an error.
    ///
    /// Logs the error and updates ``healthKitError`` for UI display.
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Workout session error: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.healthKitError = error
            self.workoutActive = false
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension HealthKitManager: HKLiveWorkoutBuilderDelegate {
    /// Called when the workout builder receives new event data.
    ///
    /// Currently a no-op; events like pause/resume are not yet implemented.
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Workout events (pause, resume, etc.) — not used in Phase 1
    }

    /// Called when the workout builder receives new sample data.
    ///
    /// Extracts heart rate from the builder's statistics as a supplement to the
    /// anchored queries. During an active `HKWorkoutSession`, the builder's
    /// `HKLiveWorkoutDataSource` may exclusively capture heart rate samples,
    /// preventing the anchored query from receiving them.
    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }

            if quantityType.identifier == HKQuantityTypeIdentifier.heartRate.rawValue {
                let statistics = workoutBuilder.statistics(for: quantityType)
                if let mostRecent = statistics?.mostRecentQuantity() {
                    let bpm = mostRecent.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    samplesQueue.sync {
                        heartRateSamples.append(bpm)
                    }
                    DispatchQueue.main.async {
                        self.currentHeartRate = bpm
                    }
                }
            }
        }
    }
}

// MARK: - HealthKit Errors

/// Error types for HealthKit-related failures in the watch app.
enum HealthKitError: Error, LocalizedError {
    /// HealthKit is not available on this device (e.g. older hardware, MDM restriction).
    case notAvailable

    /// The user denied authorization for the requested HealthKit data types.
    case authorizationDenied

    /// The workout session could not be started.
    case workoutStartFailed(underlying: Error)

    /// The workout could not be saved to Apple Health.
    case workoutSaveFailed(underlying: Error)

    /// A user-facing description of the error.
    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device."
        case .authorizationDenied:
            return "HealthKit access was denied. You can enable it in Settings > Privacy > Health."
        case .workoutStartFailed(let error):
            return "Could not start workout: \(error.localizedDescription)"
        case .workoutSaveFailed(let error):
            return "Could not save workout: \(error.localizedDescription)"
        }
    }
}
