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

/// Errors that can occur during GitHub route operations.
enum GitHubRouteError: Error, LocalizedError {
    /// The GitHub API returned an unexpected HTTP status code.
    case httpError(statusCode: Int, message: String)
    /// The API response could not be decoded.
    case invalidResponse(String)
    /// The bot token is missing or invalid.
    case authenticationFailed
    /// A network request failed after all retry attempts.
    case networkError(Error)
    /// The route index could not be fetched or decoded.
    case indexFetchFailed(String)
    /// The route data at the given path could not be fetched.
    case routeFetchFailed(String)

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let message):
            return "GitHub API error (\(code)): \(message)"
        case .invalidResponse(let detail):
            return "Invalid GitHub response: \(detail)"
        case .authenticationFailed:
            return "GitHub authentication failed — please check the app configuration"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .indexFetchFailed(let detail):
            return "Could not load community routes: \(detail)"
        case .routeFetchFailed(let detail):
            return "Could not download route: \(detail)"
        }
    }
}

/// Manages all communication with the OpenHikerRoutes GitHub repository.
///
/// This actor provides three main capabilities:
/// 1. **Upload** — creates a pull request with a new route (JSON + GPX + README + photos)
/// 2. **Browse** — fetches and caches the `index.json` master index for route discovery
/// 3. **Download** — fetches individual `route.json` files and photos for offline use
///
/// ## Authentication
/// Uses an obfuscated bot token embedded in the binary. The token has only
/// `contents:write` and `pull_requests:write` scope on the OpenHikerRoutes repository.
/// Since all uploads go through pull requests that require approval, the blast radius
/// of a leaked token is limited to spam PRs (which can be closed and the token rotated).
///
/// ## Rate Limiting
/// GitHub API allows 5000 requests/hour with authentication. All requests include
/// exponential backoff retry (up to 4 attempts) for transient network failures.
///
/// ## Thread Safety
/// This is a Swift Actor, providing automatic thread-safe access to all mutable state.
actor GitHubRouteService {

    // MARK: - Configuration

    /// GitHub repository owner (organization or user).
    private static let repoOwner = "hherb"

    /// GitHub repository name for shared routes.
    private static let repoName = "OpenHikerRoutes"

    /// Default branch name in the repository.
    private static let defaultBranch = "main"

    /// Base URL for the GitHub REST API.
    private static let apiBaseURL = "https://api.github.com"

    /// Base URL for fetching raw file content from the repository.
    private static let rawContentBaseURL = "https://raw.githubusercontent.com/\(repoOwner)/\(repoName)/\(defaultBranch)"

    /// Maximum number of retry attempts for failed network requests.
    private static let maxRetryAttempts = 4

    /// Base delay in seconds for exponential backoff (doubled on each retry).
    private static let baseRetryDelaySec: UInt64 = 2

    /// User-Agent header value for API requests (required by GitHub).
    private static let userAgent = "OpenHiker/1.0 (iOS; community route sharing)"

    /// Timeout for individual API requests in seconds.
    private static let requestTimeoutSec: TimeInterval = 30

    /// Timeout for the entire resource download in seconds.
    private static let resourceTimeoutSec: TimeInterval = 120

    /// XOR key used for token obfuscation/deobfuscation.
    private static let tokenObfuscationKey: UInt8 = 0xA5

    /// Number of UUID characters used in branch name suffixes.
    private static let branchNameUUIDPrefixLength = 8

    /// Git file mode for regular (non-executable) files.
    private static let gitBlobFileMode = "100644"

    /// Default search radius in kilometers for proximity filtering.
    static let defaultSearchRadiusKm: Double = 50

    /// Conversion factor from degrees to radians.
    private static let degreesToRadians: Double = .pi / 180.0

    /// Meters per kilometer.
    private static let metersPerKilometer: Double = 1000.0

    /// Seconds per hour.
    private static let secondsPerHour = 3600

    /// Seconds per minute.
    private static let secondsPerMinute = 60

    /// Nanoseconds per second, used for `Task.sleep` calculations.
    private static let nanosecondsPerSecond: UInt64 = 1_000_000_000

    // MARK: - State

    /// The URL session configured for GitHub API calls.
    private let session: URLSession

    /// Cached route index, refreshed on each browse.
    private var cachedIndex: RouteIndex?

    /// Timestamp of the last successful index fetch.
    private var indexFetchedAt: Date?

    /// Maximum age in seconds before the cached index is considered stale.
    private static let indexCacheMaxAgeSec: TimeInterval = 300 // 5 minutes

    // MARK: - Singleton

    /// Shared singleton instance.
    static let shared = GitHubRouteService()

    /// Creates the service with a configured URL session.
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Self.requestTimeoutSec
        config.timeoutIntervalForResource = Self.resourceTimeoutSec
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    // MARK: - Token Management

    /// Retrieves the obfuscated GitHub bot token.
    ///
    /// The token is XOR-obfuscated to prevent casual extraction via `strings` on the binary.
    /// This is NOT cryptographic security — it is a speed bump against idle curiosity.
    /// The real security comes from PR-based moderation (token can only create PRs, not
    /// push directly to main).
    ///
    /// **Important:** Replace the placeholder values with your actual obfuscated token
    /// before shipping. Use ``obfuscateToken(_:key:)`` to generate the byte arrays.
    ///
    /// - Returns: The deobfuscated token string, or `nil` if deobfuscation fails.
    private func getToken() -> String? {
        // PLACEHOLDER: Replace with your actual obfuscated token bytes.
        // Generate with: RouteServiceTokenHelper.obfuscateToken("ghp_your_token_here", key: 0xA5)
        // The obfuscated bytes and the XOR key must match.
        let obfuscatedBytes: [UInt8] = [
            // Placeholder — replace before deployment
            0x00
        ]
        let deobfuscated = obfuscatedBytes.map { $0 ^ Self.tokenObfuscationKey }
        return String(bytes: deobfuscated, encoding: .utf8)
    }

    // MARK: - Upload (Create Pull Request)

    /// Uploads a shared route to the community repository as a pull request.
    ///
    /// Creates a new branch, commits all route files (route.json, route.gpx, README.md,
    /// and photos), then opens a PR against the default branch. The PR must be approved
    /// by a maintainer before the route appears in the index.
    ///
    /// ## File structure created:
    /// ```
    /// routes/<country>/<slug>/
    ///   route.json
    ///   route.gpx
    ///   README.md
    ///   photos/
    ///     <filename>.jpg
    /// ```
    ///
    /// - Parameters:
    ///   - route: The ``SharedRoute`` to upload.
    ///   - photoData: Dictionary mapping photo filenames to their JPEG data.
    /// - Returns: The URL of the created pull request.
    /// - Throws: ``GitHubRouteError`` if any API call fails.
    func uploadRoute(_ route: SharedRoute, photoData: [String: Data]) async throws -> String {
        guard let token = getToken() else {
            throw GitHubRouteError.authenticationFailed
        }

        let slug = RouteExporter.slugify(route.name)
        let country = route.region.country.lowercased()
        let basePath = "routes/\(country)/\(slug)"
        let branchName = "route/\(slug)-\(route.id.uuidString.prefix(Self.branchNameUUIDPrefixLength).lowercased())"

        // Step 1: Get the SHA of the default branch HEAD commit
        let defaultBranchSHA = try await getDefaultBranchSHA(token: token)

        // Step 2: Get the tree SHA from the HEAD commit (commits and trees have different SHAs)
        let baseTreeSHA = try await getTreeSHA(forCommit: defaultBranchSHA, token: token)

        // Step 3: Create a new branch from HEAD
        try await createBranch(name: branchName, fromSHA: defaultBranchSHA, token: token)

        // Step 4: Build the file tree
        var files: [(path: String, content: Data)] = []

        // route.json
        let jsonData = try RouteExporter.toJSON(route)
        files.append((path: "\(basePath)/route.json", content: jsonData))

        // route.gpx
        let gpxData = RouteExporter.toGPX(route)
        files.append((path: "\(basePath)/route.gpx", content: gpxData))

        // README.md
        let readmeContent = RouteExporter.toMarkdown(route)
        files.append((path: "\(basePath)/README.md", content: Data(readmeContent.utf8)))

        // Photos
        for (filename, data) in photoData {
            files.append((path: "\(basePath)/photos/\(filename)", content: data))
        }

        // Step 5: Create blobs for each file
        var treeEntries: [[String: String]] = []
        for file in files {
            let blobSHA = try await createBlob(content: file.content, token: token)
            treeEntries.append([
                "path": file.path,
                "mode": Self.gitBlobFileMode,
                "type": "blob",
                "sha": blobSHA
            ])
        }

        // Step 6: Create a tree (using the tree SHA, not the commit SHA)
        let treeSHA = try await createTree(entries: treeEntries, baseTreeSHA: baseTreeSHA, token: token)

        // Step 7: Create a commit
        let commitMessage = "Add route: \(route.name)\n\nActivity: \(route.activityType.displayName)\nRegion: \(route.region.area), \(route.region.country)\nAuthor: \(route.author)"
        let commitSHA = try await createCommit(
            message: commitMessage,
            treeSHA: treeSHA,
            parentSHA: defaultBranchSHA,
            token: token
        )

        // Step 8: Update the branch ref to point to the new commit
        try await updateRef(branch: branchName, sha: commitSHA, token: token)

        // Step 9: Create the pull request
        let prURL = try await createPullRequest(
            title: "Add route: \(route.name)",
            body: buildPRDescription(route),
            head: branchName,
            token: token
        )

        return prURL
    }

    // MARK: - Browse (Fetch Index)

    /// Fetches the community route index for browsing and searching.
    ///
    /// Returns a cached version if the cache is less than 5 minutes old.
    /// Otherwise fetches `index.json` from the repository's raw content URL.
    ///
    /// - Parameter forceRefresh: If `true`, bypasses the cache and fetches fresh data.
    /// - Returns: The ``RouteIndex`` containing all route summaries.
    /// - Throws: ``GitHubRouteError/indexFetchFailed(_:)`` if the fetch fails.
    func fetchIndex(forceRefresh: Bool = false) async throws -> RouteIndex {
        // Return cached index if still fresh
        if !forceRefresh,
           let cached = cachedIndex,
           let fetchedAt = indexFetchedAt,
           Date().timeIntervalSince(fetchedAt) < Self.indexCacheMaxAgeSec {
            return cached
        }

        let urlString = "\(Self.rawContentBaseURL)/index.json"
        guard let url = URL(string: urlString) else {
            throw GitHubRouteError.indexFetchFailed("Invalid URL: \(urlString)")
        }

        let data = try await fetchWithRetry(url: url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let index = try decoder.decode(RouteIndex.self, from: data)
            cachedIndex = index
            indexFetchedAt = Date()
            return index
        } catch {
            throw GitHubRouteError.indexFetchFailed(error.localizedDescription)
        }
    }

    /// Filters index entries by activity type and geographic proximity.
    ///
    /// - Parameters:
    ///   - entries: The route entries to filter.
    ///   - activityType: If non-nil, only routes matching this activity type are returned.
    ///   - latitude: Center latitude for geographic filtering, or `nil` for no geo filter.
    ///   - longitude: Center longitude for geographic filtering, or `nil` for no geo filter.
    ///   - radiusKm: Maximum distance from the center point in kilometers.
    /// - Returns: Filtered and sorted array of route entries.
    func filterRoutes(
        _ entries: [RouteIndexEntry],
        activityType: ActivityType?,
        nearLatitude latitude: Double?,
        nearLongitude longitude: Double?,
        radiusKm: Double = GitHubRouteService.defaultSearchRadiusKm
    ) -> [RouteIndexEntry] {
        var filtered = entries

        // Filter by activity type
        if let activityType = activityType {
            filtered = filtered.filter { $0.activityType == activityType }
        }

        // Filter by geographic proximity
        if let lat = latitude, let lon = longitude {
            filtered = filtered.filter { entry in
                let centerLat = entry.boundingBox.centerLatitude
                let centerLon = entry.boundingBox.centerLongitude
                let distanceKm = haversineDistanceKm(
                    lat1: lat, lon1: lon,
                    lat2: centerLat, lon2: centerLon
                )
                return distanceKm <= radiusKm
            }

            // Sort by distance from center
            filtered.sort { a, b in
                let distA = haversineDistanceKm(
                    lat1: lat, lon1: lon,
                    lat2: a.boundingBox.centerLatitude, lon2: a.boundingBox.centerLongitude
                )
                let distB = haversineDistanceKm(
                    lat1: lat, lon1: lon,
                    lat2: b.boundingBox.centerLatitude, lon2: b.boundingBox.centerLongitude
                )
                return distA < distB
            }
        }

        return filtered
    }

    // MARK: - Download (Fetch Route)

    /// Downloads a full shared route from the community repository.
    ///
    /// Fetches the `route.json` file at the given path and decodes it.
    ///
    /// - Parameter path: The relative path in the repository (e.g., "routes/us/mount-tam-loop").
    /// - Returns: The decoded ``SharedRoute``.
    /// - Throws: ``GitHubRouteError/routeFetchFailed(_:)`` if the fetch or decode fails.
    func fetchRoute(at path: String) async throws -> SharedRoute {
        let urlString = "\(Self.rawContentBaseURL)/\(path)/route.json"
        guard let url = URL(string: urlString) else {
            throw GitHubRouteError.routeFetchFailed("Invalid URL: \(urlString)")
        }

        let data = try await fetchWithRetry(url: url)

        do {
            return try RouteExporter.fromJSON(data)
        } catch {
            throw GitHubRouteError.routeFetchFailed("JSON decode error: \(error.localizedDescription)")
        }
    }

    /// Downloads a photo from a shared route.
    ///
    /// - Parameters:
    ///   - filename: The photo filename (e.g., "summit_view.jpg").
    ///   - routePath: The route's directory path in the repository.
    /// - Returns: The raw JPEG data.
    /// - Throws: ``GitHubRouteError/routeFetchFailed(_:)`` if the download fails.
    func fetchPhoto(filename: String, routePath: String) async throws -> Data {
        let urlString = "\(Self.rawContentBaseURL)/\(routePath)/photos/\(filename)"
        guard let url = URL(string: urlString) else {
            throw GitHubRouteError.routeFetchFailed("Invalid photo URL: \(urlString)")
        }

        return try await fetchWithRetry(url: url)
    }

    // MARK: - Git Data API Helpers

    /// Fetches the SHA of the latest commit on the default branch.
    ///
    /// - Parameter token: GitHub API token.
    /// - Returns: The commit SHA hex string.
    /// - Throws: ``GitHubRouteError`` on failure.
    private func getDefaultBranchSHA(token: String) async throws -> String {
        let url = apiURL("git/ref/heads/\(Self.defaultBranch)")
        let data = try await authenticatedRequest(url: url, method: "GET", token: token)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let object = json["object"] as? [String: Any],
              let sha = object["sha"] as? String else {
            throw GitHubRouteError.invalidResponse("Could not parse branch SHA")
        }
        return sha
    }

    /// Fetches the tree SHA from a commit object.
    ///
    /// Git commits and trees are different objects with different SHAs.
    /// The GitHub Create Tree API requires a tree SHA for `base_tree`, not a commit SHA.
    ///
    /// - Parameters:
    ///   - commitSHA: The commit SHA to look up.
    ///   - token: GitHub API token.
    /// - Returns: The tree SHA associated with the commit.
    /// - Throws: ``GitHubRouteError`` on failure.
    private func getTreeSHA(forCommit commitSHA: String, token: String) async throws -> String {
        let url = apiURL("git/commits/\(commitSHA)")
        let data = try await authenticatedRequest(url: url, method: "GET", token: token)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tree = json["tree"] as? [String: Any],
              let treeSHA = tree["sha"] as? String else {
            throw GitHubRouteError.invalidResponse("Could not parse tree SHA from commit")
        }
        return treeSHA
    }

    /// Creates a new branch from the given SHA.
    ///
    /// - Parameters:
    ///   - name: The branch name (without `refs/heads/` prefix).
    ///   - fromSHA: The commit SHA to create the branch from.
    ///   - token: GitHub API token.
    /// - Throws: ``GitHubRouteError`` on failure.
    private func createBranch(name: String, fromSHA: String, token: String) async throws {
        let url = apiURL("git/refs")
        let body: [String: Any] = [
            "ref": "refs/heads/\(name)",
            "sha": fromSHA
        ]
        _ = try await authenticatedRequest(url: url, method: "POST", body: body, token: token)
    }

    /// Creates a blob (file content) in the repository.
    ///
    /// - Parameters:
    ///   - content: The file content as raw data.
    ///   - token: GitHub API token.
    /// - Returns: The SHA of the created blob.
    /// - Throws: ``GitHubRouteError`` on failure.
    private func createBlob(content: Data, token: String) async throws -> String {
        let url = apiURL("git/blobs")
        let body: [String: Any] = [
            "content": content.base64EncodedString(),
            "encoding": "base64"
        ]
        let responseData = try await authenticatedRequest(url: url, method: "POST", body: body, token: token)
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let sha = json["sha"] as? String else {
            throw GitHubRouteError.invalidResponse("Could not parse blob SHA")
        }
        return sha
    }

    /// Creates a git tree from an array of blob entries.
    ///
    /// - Parameters:
    ///   - entries: Array of tree entry dictionaries with `path`, `mode`, `type`, `sha` keys.
    ///   - baseTreeSHA: The SHA of the parent tree to base this tree on.
    ///   - token: GitHub API token.
    /// - Returns: The SHA of the created tree.
    /// - Throws: ``GitHubRouteError`` on failure.
    private func createTree(entries: [[String: String]], baseTreeSHA: String, token: String) async throws -> String {
        let url = apiURL("git/trees")
        let body: [String: Any] = [
            "base_tree": baseTreeSHA,
            "tree": entries
        ]
        let responseData = try await authenticatedRequest(url: url, method: "POST", body: body, token: token)
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let sha = json["sha"] as? String else {
            throw GitHubRouteError.invalidResponse("Could not parse tree SHA")
        }
        return sha
    }

    /// Creates a commit with the given tree and parent.
    ///
    /// - Parameters:
    ///   - message: The commit message.
    ///   - treeSHA: The SHA of the tree for this commit.
    ///   - parentSHA: The SHA of the parent commit.
    ///   - token: GitHub API token.
    /// - Returns: The SHA of the created commit.
    /// - Throws: ``GitHubRouteError`` on failure.
    private func createCommit(message: String, treeSHA: String, parentSHA: String, token: String) async throws -> String {
        let url = apiURL("git/commits")
        let body: [String: Any] = [
            "message": message,
            "tree": treeSHA,
            "parents": [parentSHA]
        ]
        let responseData = try await authenticatedRequest(url: url, method: "POST", body: body, token: token)
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let sha = json["sha"] as? String else {
            throw GitHubRouteError.invalidResponse("Could not parse commit SHA")
        }
        return sha
    }

    /// Updates a branch ref to point to a new commit.
    ///
    /// - Parameters:
    ///   - branch: The branch name (without `refs/heads/` prefix).
    ///   - sha: The commit SHA to update to.
    ///   - token: GitHub API token.
    /// - Throws: ``GitHubRouteError`` on failure.
    private func updateRef(branch: String, sha: String, token: String) async throws {
        let url = apiURL("git/refs/heads/\(branch)")
        let body: [String: Any] = [
            "sha": sha,
            "force": true
        ]
        _ = try await authenticatedRequest(url: url, method: "PATCH", body: body, token: token)
    }

    /// Creates a pull request from the given branch.
    ///
    /// - Parameters:
    ///   - title: The PR title.
    ///   - body: The PR description in Markdown.
    ///   - head: The source branch name.
    ///   - token: GitHub API token.
    /// - Returns: The HTML URL of the created pull request.
    /// - Throws: ``GitHubRouteError`` on failure.
    private func createPullRequest(title: String, body: String, head: String, token: String) async throws -> String {
        let url = URL(string: "\(Self.apiBaseURL)/repos/\(Self.repoOwner)/\(Self.repoName)/pulls")!
        let requestBody: [String: Any] = [
            "title": title,
            "body": body,
            "head": head,
            "base": Self.defaultBranch
        ]
        let responseData = try await authenticatedRequest(url: url, method: "POST", body: requestBody, token: token)
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let htmlURL = json["html_url"] as? String else {
            throw GitHubRouteError.invalidResponse("Could not parse PR URL")
        }
        return htmlURL
    }

    // MARK: - Network Helpers

    /// Constructs a GitHub API URL for the configured repository.
    ///
    /// - Parameter endpoint: The API endpoint path (e.g., "git/refs").
    /// - Returns: The full API URL.
    private func apiURL(_ endpoint: String) -> URL {
        URL(string: "\(Self.apiBaseURL)/repos/\(Self.repoOwner)/\(Self.repoName)/\(endpoint)")!
    }

    /// Performs an authenticated GitHub API request with JSON body.
    ///
    /// Includes retry with exponential backoff for transient failures.
    ///
    /// - Parameters:
    ///   - url: The API endpoint URL.
    ///   - method: HTTP method (GET, POST, PATCH, etc.).
    ///   - body: Optional JSON body dictionary.
    ///   - token: GitHub API token.
    /// - Returns: The response body data.
    /// - Throws: ``GitHubRouteError`` on failure after all retries.
    private func authenticatedRequest(
        url: URL,
        method: String,
        body: [String: Any]? = nil,
        token: String
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return try await performWithRetry(request: request)
    }

    /// Fetches raw content from a URL with retry.
    ///
    /// Used for fetching `index.json`, `route.json`, and photo files from
    /// the raw content URL (which does not require authentication).
    ///
    /// - Parameter url: The URL to fetch.
    /// - Returns: The response body data.
    /// - Throws: ``GitHubRouteError`` on failure after all retries.
    private func fetchWithRetry(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        return try await performWithRetry(request: request)
    }

    /// Performs a URL request with exponential backoff retry.
    ///
    /// Retries up to ``maxRetryAttempts`` times with delays of 2s, 4s, 8s, 16s.
    /// Only retries on network errors and 5xx server errors, not on 4xx client errors.
    ///
    /// - Parameter request: The URL request to perform.
    /// - Returns: The response body data.
    /// - Throws: ``GitHubRouteError`` if all retries are exhausted.
    private func performWithRetry(request: URLRequest) async throws -> Data {
        var lastError: Error?

        for attempt in 0..<Self.maxRetryAttempts {
            do {
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw GitHubRouteError.invalidResponse("Not an HTTP response")
                }

                switch httpResponse.statusCode {
                case 200...299:
                    return data
                case 401, 403:
                    throw GitHubRouteError.authenticationFailed
                case 400...499:
                    // Client errors — do not retry
                    let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw GitHubRouteError.httpError(statusCode: httpResponse.statusCode, message: message)
                default:
                    // Server errors — retry
                    let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                    lastError = GitHubRouteError.httpError(statusCode: httpResponse.statusCode, message: message)
                }
            } catch let error as GitHubRouteError {
                // Don't retry auth or client errors
                switch error {
                case .authenticationFailed:
                    throw error
                case .httpError(let statusCode, _) where (400...499).contains(statusCode):
                    throw error
                default:
                    lastError = error
                }
            } catch {
                lastError = error
            }

            // Exponential backoff: 2s, 4s, 8s, 16s
            if attempt < Self.maxRetryAttempts - 1 {
                let delay = Self.baseRetryDelaySec * UInt64(1 << attempt)
                try await Task.sleep(nanoseconds: delay * Self.nanosecondsPerSecond)
            }
        }

        if let error = lastError as? GitHubRouteError {
            throw error
        }
        throw GitHubRouteError.networkError(lastError ?? NSError(domain: "GitHubRouteService", code: -1))
    }

    // MARK: - PR Description Builder

    /// Builds a Markdown description for a route upload pull request.
    ///
    /// - Parameter route: The shared route being uploaded.
    /// - Returns: A Markdown string for the PR body.
    private func buildPRDescription(_ route: SharedRoute) -> String {
        let distanceKm = route.stats.distanceMeters / Self.metersPerKilometer
        let durationHours = Int(route.stats.durationSeconds) / Self.secondsPerHour
        let durationMinutes = (Int(route.stats.durationSeconds) % Self.secondsPerHour) / Self.secondsPerMinute

        return """
        ## New Route: \(route.name)

        **Activity:** \(route.activityType.displayName)
        **Author:** \(route.author)
        **Region:** \(route.region.area), \(route.region.country)

        | Stat | Value |
        |------|-------|
        | Distance | \(String(format: "%.1f km", distanceKm)) |
        | Elevation Gain | \(String(format: "%.0f m", route.stats.elevationGainMeters)) |
        | Duration | \(durationHours)h \(durationMinutes)m |
        | Track Points | \(route.track.count) |
        | Waypoints | \(route.waypoints.count) |
        | Photos | \(route.photos.count) |

        \(route.description.isEmpty ? "" : "> \(route.description)")

        ---
        *Submitted via OpenHiker app*
        """
    }

    // MARK: - Haversine Distance

    /// Earth's mean radius in kilometers.
    private static let earthRadiusKm: Double = 6371.0

    /// Calculates the great-circle distance between two points using the Haversine formula.
    ///
    /// - Parameters:
    ///   - lat1: Latitude of the first point in degrees.
    ///   - lon1: Longitude of the first point in degrees.
    ///   - lat2: Latitude of the second point in degrees.
    ///   - lon2: Longitude of the second point in degrees.
    /// - Returns: Distance in kilometers.
    private func haversineDistanceKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let dLat = (lat2 - lat1) * Self.degreesToRadians
        let dLon = (lon2 - lon1) * Self.degreesToRadians
        let lat1Rad = lat1 * Self.degreesToRadians
        let lat2Rad = lat2 * Self.degreesToRadians

        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1Rad) * cos(lat2Rad) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))

        return Self.earthRadiusKm * c
    }
}

// MARK: - Token Helper

/// Utility for generating obfuscated token byte arrays.
///
/// Run this once in a playground or test to generate the byte array for your token,
/// then paste the result into ``GitHubRouteService/getToken()``.
///
/// ```swift
/// let bytes = RouteServiceTokenHelper.obfuscateToken("ghp_your_token", key: 0xA5)
/// print(bytes) // Paste this into getToken()
/// ```
enum RouteServiceTokenHelper {
    /// XOR-obfuscates a token string for embedding in the binary.
    ///
    /// - Parameters:
    ///   - token: The plaintext GitHub token.
    ///   - key: The XOR key byte.
    /// - Returns: An array of obfuscated bytes.
    static func obfuscateToken(_ token: String, key: UInt8) -> [UInt8] {
        Array(token.utf8).map { $0 ^ key }
    }
}
