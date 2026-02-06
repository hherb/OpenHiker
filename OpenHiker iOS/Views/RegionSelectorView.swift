#if os(iOS)
import SwiftUI
import MapKit
import CoreLocation

struct RegionSelectorView: View {
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectionRect: CGRect?
    @State private var isSelecting = false
    @State private var selectedRegion: MKCoordinateRegion?
    @State private var showDownloadSheet = false
    @State private var regionName = ""
    @State private var showSearchSheet = false
    @State private var isDownloading = false
    @State private var downloadProgress: RegionDownloadProgress?
    @State private var downloadError: Error?
    @State private var minZoom: Int = 12
    @State private var maxZoom: Int = 16
    @StateObject private var locationManager = LocationManageriOS()
    @StateObject private var searchCompleter = LocationSearchCompleter()

    // Persist the last viewed location
    @AppStorage("lastLatitude") private var lastLatitude: Double = 37.8651  // Yosemite default
    @AppStorage("lastLongitude") private var lastLongitude: Double = -119.5383
    @AppStorage("lastSpan") private var lastSpan: Double = 0.5

    private let tileDownloader = TileDownloader()
    @ObservedObject private var regionStorage = RegionStorage.shared
    @EnvironmentObject private var watchConnectivity: WatchConnectivityManager

    var body: some View {
        NavigationStack {
            ZStack {
                // Map
                Map(position: $cameraPosition) {
                    // Show selection rectangle as annotation if we have one
                    if let region = selectedRegion {
                        MapPolygon(coordinates: regionCorners(region))
                            .foregroundStyle(.blue.opacity(0.2))
                            .stroke(.blue, lineWidth: 2)
                    }

                    // Track trail breadcrumb
                    if locationManager.trackPoints.count >= 2 {
                        MapPolyline(coordinates: locationManager.trackPoints.map(\.coordinate))
                            .stroke(.orange, lineWidth: 4)
                    }

                    // User position marker
                    UserAnnotation()
                }
                .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }

                // Selection overlay - only blocks gestures during active selection
                if isSelecting {
                    SelectionOverlay(selectionRect: $selectionRect)
                }

                // Custom controls overlay
                VStack {
                    HStack {
                        Spacer()

                        VStack(spacing: 8) {
                            // Search location button
                            Button {
                                showSearchSheet = true
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.blue)
                                    .frame(width: 44, height: 44)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }

                            // Center on location button
                            Button {
                                centerOnUserLocation()
                            } label: {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.blue)
                                    .frame(width: 44, height: 44)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }

                            // Track recording toggle
                            Button {
                                if locationManager.isTracking {
                                    locationManager.stopTracking()
                                } else {
                                    locationManager.requestLocationPermission()
                                    locationManager.startTracking()
                                }
                            } label: {
                                Image(systemName: locationManager.isTracking ? "record.circle.fill" : "record.circle")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(locationManager.isTracking ? .red : .blue)
                                    .frame(width: 44, height: 44)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(.trailing, 8)
                        .padding(.top, 60) // Below navigation bar
                    }

                    Spacer()

                    if isDownloading, let progress = downloadProgress {
                        downloadProgressCard(progress)
                    } else if selectedRegion != nil {
                        selectedRegionInfo
                    } else {
                        instructionsCard
                    }
                }
                .padding()
            }
            .navigationTitle("Select Region")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSelecting ? "Done" : "Select Area") {
                        if isSelecting {
                            finalizeSelection()
                            // Show download sheet immediately if selection was successful
                            if selectedRegion != nil {
                                showDownloadSheet = true
                            }
                        }
                        isSelecting.toggle()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isDownloading)
                }

                if selectedRegion != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Clear") {
                            selectedRegion = nil
                            selectionRect = nil
                        }
                    }
                }
            }
            .sheet(isPresented: $showDownloadSheet) {
                DownloadConfigSheet(
                    region: selectedRegion!,
                    regionName: $regionName,
                    minZoom: $minZoom,
                    maxZoom: $maxZoom,
                    onDownload: startDownload
                )
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showSearchSheet) {
                LocationSearchSheet(
                    searchCompleter: searchCompleter,
                    onSelectLocation: { coordinate in
                        showSearchSheet = false
                        saveLastLocation(coordinate: coordinate, span: 0.2)
                        withAnimation {
                            cameraPosition = .region(MKCoordinateRegion(
                                center: coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
                            ))
                        }
                    }
                )
                .presentationDetents([.medium, .large])
            }
        }
        .onAppear {
            // Load the last viewed location
            let center = CLLocationCoordinate2D(latitude: lastLatitude, longitude: lastLongitude)
            cameraPosition = .region(MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: lastSpan, longitudeDelta: lastSpan)
            ))
        }
        .onChange(of: locationManager.currentLocation) { _, newLocation in
            // When location updates, center map if user requested it
            if locationManager.shouldCenterOnNextUpdate, let location = newLocation {
                locationManager.shouldCenterOnNextUpdate = false
                saveLastLocation(coordinate: location.coordinate, span: 0.1)
                withAnimation {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: location.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                    ))
                }
            }
        }
    }

    private var instructionsCard: some View {
        HStack {
            Image(systemName: "hand.draw")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading) {
                Text("Tap 'Select Area' to draw")
                    .font(.headline)
                Text("Draw a rectangle around the hiking area you want to download")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func downloadProgressCard(_ progress: RegionDownloadProgress) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Downloading...")
                        .font(.headline)

                    Text(progress.status.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Zoom level \(progress.currentZoom) • \(progress.downloadedTiles)/\(progress.totalTiles) tiles")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if progress.isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.green)
                } else {
                    ProgressView()
                }
            }

            ProgressView(value: progress.progress)
                .tint(.blue)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var selectedRegionInfo: some View {
        VStack(spacing: 12) {
            let boundingBox = BoundingBox(
                north: selectedRegion!.center.latitude + selectedRegion!.span.latitudeDelta / 2,
                south: selectedRegion!.center.latitude - selectedRegion!.span.latitudeDelta / 2,
                east: selectedRegion!.center.longitude + selectedRegion!.span.longitudeDelta / 2,
                west: selectedRegion!.center.longitude - selectedRegion!.span.longitudeDelta / 2
            )

            HStack {
                VStack(alignment: .leading) {
                    Text("Selected Area")
                        .font(.headline)

                    let area = boundingBox.areaKm2
                    Text("\(String(format: "%.1f", area)) km²")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    let tileCount = boundingBox.estimateTileCount(zoomLevels: minZoom...maxZoom)
                    Text("~\(tileCount) tiles • ~\(estimatedSize(tileCount: tileCount))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Button("Download") {
                    showDownloadSheet = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func estimatedSize(tileCount: Int) -> String {
        let bytes = Int64(tileCount) * 15_000
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func regionCorners(_ region: MKCoordinateRegion) -> [CLLocationCoordinate2D] {
        let latDelta = region.span.latitudeDelta / 2
        let lonDelta = region.span.longitudeDelta / 2
        let center = region.center

        return [
            CLLocationCoordinate2D(latitude: center.latitude + latDelta, longitude: center.longitude - lonDelta),
            CLLocationCoordinate2D(latitude: center.latitude + latDelta, longitude: center.longitude + lonDelta),
            CLLocationCoordinate2D(latitude: center.latitude - latDelta, longitude: center.longitude + lonDelta),
            CLLocationCoordinate2D(latitude: center.latitude - latDelta, longitude: center.longitude - lonDelta),
        ]
    }

    private func finalizeSelection() {
        // Use the visible region - if user drew a rectangle, scale it down
        // Otherwise use the center portion of the visible map
        guard let visibleRegion = cameraPosition.region else { return }

        let scaleFactor: Double
        if selectionRect != nil && selectionRect!.width > 50 && selectionRect!.height > 50 {
            // User drew a meaningful rectangle - use a smaller portion
            scaleFactor = 0.5
        } else {
            // No rectangle or too small - use center 60% of visible region
            scaleFactor = 0.6
        }

        selectedRegion = MKCoordinateRegion(
            center: visibleRegion.center,
            span: MKCoordinateSpan(
                latitudeDelta: visibleRegion.span.latitudeDelta * scaleFactor,
                longitudeDelta: visibleRegion.span.longitudeDelta * scaleFactor
            )
        )

        // Clear the selection rectangle
        selectionRect = nil
    }

    private func startDownload() {
        guard let region = selectedRegion else { return }

        let boundingBox = BoundingBox(
            north: region.center.latitude + region.span.latitudeDelta / 2,
            south: region.center.latitude - region.span.latitudeDelta / 2,
            east: region.center.longitude + region.span.longitudeDelta / 2,
            west: region.center.longitude - region.span.longitudeDelta / 2
        )

        let request = RegionSelectionRequest(
            name: regionName.isEmpty ? "Region \(Date().formatted(date: .abbreviated, time: .omitted))" : regionName,
            boundingBox: boundingBox,
            zoomLevels: minZoom...maxZoom
        )

        showDownloadSheet = false
        isDownloading = true
        selectedRegion = nil

        Task {
            do {
                var totalTiles = 0
                let mbtilesURL = try await tileDownloader.downloadRegion(request) { progress in
                    totalTiles = progress.totalTiles
                    Task { @MainActor in
                        self.downloadProgress = progress
                    }
                }

                await MainActor.run {
                    // Save the region to storage
                    let region = regionStorage.createRegion(
                        from: request,
                        mbtilesURL: mbtilesURL,
                        tileCount: totalTiles
                    )
                    regionStorage.saveRegion(region)

                    // Transfer to watch if connected
                    if watchConnectivity.isPaired {
                        let metadata = regionStorage.metadata(for: region)
                        watchConnectivity.transferMBTilesFile(at: mbtilesURL, metadata: metadata)
                    }

                    isDownloading = false
                    downloadProgress = nil
                    print("Download complete: \(mbtilesURL.path)")
                }
            } catch {
                await MainActor.run {
                    isDownloading = false
                    downloadError = error
                    print("Download failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func centerOnUserLocation() {
        locationManager.shouldCenterOnNextUpdate = true
        locationManager.requestLocationPermission()

        // If we already have a location, center immediately
        if let location = locationManager.currentLocation {
            locationManager.shouldCenterOnNextUpdate = false
            saveLastLocation(coordinate: location.coordinate, span: 0.1)
            withAnimation {
                cameraPosition = .region(MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                ))
            }
        }
    }

    private func saveLastLocation(coordinate: CLLocationCoordinate2D, span: Double) {
        lastLatitude = coordinate.latitude
        lastLongitude = coordinate.longitude
        lastSpan = span
    }
}

// MARK: - Location Search

class LocationSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var searchQuery = ""
    @Published var completions: [MKLocalSearchCompletion] = []
    @Published var isSearching = false

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func search(_ query: String) {
        searchQuery = query
        if query.isEmpty {
            completions = []
            isSearching = false
        } else {
            isSearching = true
            completer.queryFragment = query
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completions = completer.results
        isSearching = false
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("Search completer error: \(error.localizedDescription)")
        isSearching = false
    }

    func getCoordinate(for completion: MKLocalSearchCompletion) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)

        do {
            let response = try await search.start()
            return response.mapItems.first?.placemark.coordinate
        } catch {
            print("Search error: \(error.localizedDescription)")
            return nil
        }
    }
}

struct LocationSearchSheet: View {
    @ObservedObject var searchCompleter: LocationSearchCompleter
    let onSelectLocation: (CLLocationCoordinate2D) -> Void

    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search results
                if searchCompleter.completions.isEmpty && !searchText.isEmpty && !searchCompleter.isSearching {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List(searchCompleter.completions, id: \.self) { completion in
                        Button {
                            Task {
                                if let coordinate = await searchCompleter.getCoordinate(for: completion) {
                                    onSelectLocation(coordinate)
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(completion.title)
                                    .foregroundStyle(.primary)
                                if !completion.subtitle.isEmpty {
                                    Text(completion.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Search Location")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search for a place")
            .onChange(of: searchText) { _, newValue in
                searchCompleter.search(newValue)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Location Manager for iOS

class LocationManageriOS: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isTracking = false
    @Published var trackPoints: [CLLocation] = []
    var shouldCenterOnNextUpdate = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.showsBackgroundLocationIndicator = true
        manager.activityType = .fitness
        authorizationStatus = manager.authorizationStatus
    }

    func requestLocationPermission() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func startTracking() {
        trackPoints.removeAll()
        isTracking = true
        manager.startUpdatingLocation()
    }

    func stopTracking() {
        isTracking = false
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location

        if isTracking {
            if let lastPoint = trackPoints.last {
                let distance = location.distance(from: lastPoint)
                if distance >= 5 {
                    trackPoints.append(location)
                }
            } else {
                trackPoints.append(location)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
}

// MARK: - Selection Overlay

struct SelectionOverlay: View {
    @Binding var selectionRect: CGRect?
    @State private var dragStart: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Semi-transparent overlay
                Color.black.opacity(0.3)
                    .allowsHitTesting(true)

                // Selection rectangle
                if let rect = selectionRect {
                    Rectangle()
                        .stroke(Color.blue, lineWidth: 3)
                        .background(Color.blue.opacity(0.1))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStart == nil {
                            dragStart = value.startLocation
                        }

                        if let start = dragStart {
                            let minX = min(start.x, value.location.x)
                            let minY = min(start.y, value.location.y)
                            let maxX = max(start.x, value.location.x)
                            let maxY = max(start.y, value.location.y)

                            selectionRect = CGRect(
                                x: minX,
                                y: minY,
                                width: maxX - minX,
                                height: maxY - minY
                            )
                        }
                    }
                    .onEnded { _ in
                        dragStart = nil
                    }
            )
        }
    }
}

// MARK: - Download Configuration Sheet

struct DownloadConfigSheet: View {
    let region: MKCoordinateRegion
    @Binding var regionName: String
    @Binding var minZoom: Int
    @Binding var maxZoom: Int
    let onDownload: () -> Void

    @State private var includeContours = true

    private var boundingBox: BoundingBox {
        BoundingBox(
            north: region.center.latitude + region.span.latitudeDelta / 2,
            south: region.center.latitude - region.span.latitudeDelta / 2,
            east: region.center.longitude + region.span.longitudeDelta / 2,
            west: region.center.longitude - region.span.longitudeDelta / 2
        )
    }

    private var estimatedTiles: Int {
        boundingBox.estimateTileCount(zoomLevels: minZoom...maxZoom)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Region Name", text: $regionName)
                } header: {
                    Text("Name")
                }

                Section {
                    Toggle("Include Contour Lines", isOn: $includeContours)

                    Stepper("Min Zoom: \(minZoom)", value: $minZoom, in: 8...maxZoom)
                    Stepper("Max Zoom: \(maxZoom)", value: $maxZoom, in: minZoom...18)

                    HStack {
                        Text("~\(estimatedTiles) tiles")
                        Spacer()
                        Text("~\(ByteCountFormatter.string(fromByteCount: Int64(estimatedTiles) * 15_000, countStyle: .file))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } header: {
                    Text("Options")
                } footer: {
                    Text("Higher zoom levels provide more detail but require more storage. Level 16 shows individual trails.")
                }

                Section {
                    Button(action: onDownload) {
                        HStack {
                            Spacer()
                            Label("Download Region", systemImage: "arrow.down.circle")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Download Options")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    RegionSelectorView()
}
#endif
