import SwiftUI
import MapKit

struct RegionSelectorView: View {
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectionRect: CGRect?
    @State private var isSelecting = false
    @State private var selectedRegion: MKCoordinateRegion?
    @State private var showDownloadSheet = false
    @State private var regionName = ""

    // Default to a nice hiking area (Yosemite)
    private let defaultCenter = CLLocationCoordinate2D(latitude: 37.8651, longitude: -119.5383)

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
                }
                .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
                .mapControls {
                    MapCompass()
                    MapScaleView()
                    MapUserLocationButton()
                }

                // Selection overlay
                if isSelecting {
                    SelectionOverlay(selectionRect: $selectionRect)
                }

                // Instructions overlay
                VStack {
                    Spacer()

                    if selectedRegion != nil {
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
                        }
                        isSelecting.toggle()
                    }
                    .buttonStyle(.borderedProminent)
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
                    onDownload: startDownload
                )
                .presentationDetents([.medium])
            }
        }
        .onAppear {
            cameraPosition = .region(MKCoordinateRegion(
                center: defaultCenter,
                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
            ))
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

                    let tileCount = boundingBox.estimateTileCount(zoomLevels: 12...16)
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
        // Convert screen rect to map coordinates
        // For now, use a simplified approach based on current camera
        guard let rect = selectionRect else { return }

        // This is a placeholder - in a real implementation, we'd convert
        // the screen rectangle to geographic coordinates
        // For MVP, we'll use the visible region scaled down
        if case .region(let visibleRegion) = cameraPosition {
            selectedRegion = MKCoordinateRegion(
                center: visibleRegion.center,
                span: MKCoordinateSpan(
                    latitudeDelta: visibleRegion.span.latitudeDelta * 0.5,
                    longitudeDelta: visibleRegion.span.longitudeDelta * 0.5
                )
            )
        }
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
            boundingBox: boundingBox
        )

        // TODO: Start download with TileDownloader
        print("Starting download for region: \(request.name)")
        print("Estimated size: \(request.estimatedSizeFormatted)")

        showDownloadSheet = false
        selectedRegion = nil
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
    let onDownload: () -> Void

    @State private var includeContours = true
    @State private var zoomRange: ClosedRange<Double> = 12...16

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

                    VStack(alignment: .leading) {
                        Text("Zoom Levels: \(Int(zoomRange.lowerBound))-\(Int(zoomRange.upperBound))")

                        // Simplified slider for now
                        HStack {
                            Text("12")
                            Spacer()
                            Text("16")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Options")
                } footer: {
                    Text("Higher zoom levels provide more detail but require more storage.")
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
