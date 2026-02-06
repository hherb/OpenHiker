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

import SwiftUI

/// A sheet for sharing a saved route to the OpenHikerRoutes community repository.
///
/// Presents a form where the user can review and edit route metadata before uploading:
/// - Route name (pre-filled from the saved route)
/// - Activity type picker
/// - Author name (persisted via `@AppStorage` for reuse)
/// - Country and area fields
/// - Description text
///
/// On submission, the route is converted to the shared format, photos are compressed,
/// and a pull request is created on GitHub. The user sees a progress indicator during
/// upload and a success/error message when complete.
struct RouteUploadView: View {
    /// The saved route to share.
    let route: SavedRoute

    /// The waypoints associated with this route.
    let waypoints: [Waypoint]

    /// Binding to dismiss this sheet.
    @Environment(\.dismiss) private var dismiss

    /// Persisted author display name (reused across uploads).
    @AppStorage("communityAuthorName") private var authorName = ""

    /// Persisted default country code (reused across uploads).
    @AppStorage("communityDefaultCountry") private var defaultCountry = ""

    /// Persisted default area/state (reused across uploads).
    @AppStorage("communityDefaultArea") private var defaultArea = ""

    // MARK: - Form State

    /// The route name (editable, pre-filled from saved route).
    @State private var routeName: String

    /// The selected activity type.
    @State private var activityType: ActivityType = .hiking

    /// Country code for this route.
    @State private var country: String

    /// Area/state for this route.
    @State private var area: String

    /// Route description text.
    @State private var routeDescription = ""

    // MARK: - Upload State

    /// Whether an upload is currently in progress.
    @State private var isUploading = false

    /// The URL of the created pull request (shown on success).
    @State private var pullRequestURL: String?

    /// Error message shown on upload failure.
    @State private var errorMessage: String?

    /// Whether the error alert is displayed.
    @State private var showError = false

    /// Creates a RouteUploadView pre-filled with data from the given route.
    ///
    /// - Parameters:
    ///   - route: The ``SavedRoute`` to share.
    ///   - waypoints: Waypoints associated with this route.
    init(route: SavedRoute, waypoints: [Waypoint]) {
        self.route = route
        self.waypoints = waypoints
        _routeName = State(initialValue: route.name)
        // Country and area will be set from @AppStorage defaults in onAppear
        _country = State(initialValue: "")
        _area = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            if let prURL = pullRequestURL {
                successView(prURL: prURL)
            } else {
                formView
            }
        }
        .onAppear {
            // Load persisted defaults
            if country.isEmpty { country = defaultCountry }
            if area.isEmpty { area = defaultArea }
            if routeDescription.isEmpty { routeDescription = route.comment }
        }
    }

    // MARK: - Form View

    /// The main form for editing route metadata before upload.
    private var formView: some View {
        Form {
            Section("Route Details") {
                TextField("Route Name", text: $routeName)

                Picker("Activity", selection: $activityType) {
                    ForEach(ActivityType.allCases, id: \.self) { type in
                        Label(type.displayName, systemImage: type.iconName)
                            .tag(type)
                    }
                }
            }

            Section("Author") {
                TextField("Your Name", text: $authorName)
                    .textContentType(.name)
                    .autocorrectionDisabled()
            }

            Section("Location") {
                TextField("Country Code (e.g., US, DE)", text: $country)
                    .textContentType(.countryName)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)

                TextField("Area (e.g., California, Bavaria)", text: $area)
                    .textContentType(.addressState)
            }

            Section("Description") {
                TextEditor(text: $routeDescription)
                    .frame(minHeight: 80)
            }

            Section {
                routeSummary
            } header: {
                Text("Summary")
            }

            Section {
                Button(action: upload) {
                    HStack {
                        if isUploading {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text("Uploading...")
                        } else {
                            Label("Share to Community", systemImage: "arrow.up.circle.fill")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(!isFormValid || isUploading)
            }
        }
        .navigationTitle("Share Route")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .alert("Upload Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    // MARK: - Success View

    /// Displayed after a successful upload with the PR URL.
    ///
    /// - Parameter prURL: The URL of the created pull request.
    private func successView(prURL: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Route Submitted!")
                .font(.title2)
                .fontWeight(.bold)

            Text("Your route has been submitted as a pull request. A maintainer will review and approve it before it appears in the community library.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Text(prURL)
                .font(.caption)
                .foregroundStyle(.blue)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .navigationTitle("Success")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Route Summary

    /// A read-only summary of the route statistics shown before upload.
    @AppStorage("useMetricUnits") private var useMetricUnits = true

    private var routeSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    HikeStatsFormatter.formatDistance(route.totalDistance, useMetric: useMetricUnits),
                    systemImage: "figure.walk"
                )
                Spacer()
                Label(
                    HikeStatsFormatter.formatDuration(route.duration),
                    systemImage: "clock"
                )
            }
            .font(.subheadline)

            HStack {
                Label(
                    "+\(HikeStatsFormatter.formatElevation(route.elevationGain, useMetric: useMetricUnits))",
                    systemImage: "arrow.up.right"
                )
                Spacer()
                Label(
                    "\(waypoints.count) waypoints",
                    systemImage: "mappin"
                )
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Validation

    /// Whether the form has enough valid data to submit.
    private var isFormValid: Bool {
        !routeName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !authorName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !country.trimmingCharacters(in: .whitespaces).isEmpty &&
        !area.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Upload Action

    /// Converts the route to shared format and uploads it as a GitHub PR.
    private func upload() {
        guard isFormValid else { return }
        isUploading = true

        // Persist defaults for next time
        defaultCountry = country.trimmingCharacters(in: .whitespaces).uppercased()
        defaultArea = area.trimmingCharacters(in: .whitespaces)

        Task {
            do {
                let sharedRoute = RouteExporter.toSharedRoute(
                    route,
                    activityType: activityType,
                    author: authorName.trimmingCharacters(in: .whitespaces),
                    description: routeDescription.trimmingCharacters(in: .whitespaces),
                    country: defaultCountry,
                    area: defaultArea,
                    waypoints: waypoints,
                    photos: [] // Photos will be added in a future iteration
                )

                let prURL = try await GitHubRouteService.shared.uploadRoute(
                    sharedRoute,
                    photoData: [:]
                )

                await MainActor.run {
                    pullRequestURL = prURL
                    isUploading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isUploading = false
                }
            }
        }
    }
}
