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

/// The available export formats for hike reports.
///
/// Each format targets a different use case:
/// - **Markdown**: Quick, lightweight sharing via messaging or email
/// - **PDF**: Professional multi-page report with maps and charts
/// - **GPX**: Interoperability with other hiking/GPS apps
enum ExportFormat: String, CaseIterable, Identifiable {
    /// Personal hike summary as Markdown text.
    case markdown = "Quick Summary (Markdown)"
    /// Multi-page PDF report with map, elevation chart, photos, and stats.
    case pdf = "Detailed Report (PDF)"
    /// GPX 1.1 GPS track for import into other apps.
    case gpx = "GPS Track (GPX)"

    var id: String { rawValue }

    /// SF Symbol icon name for this format.
    var iconName: String {
        switch self {
        case .markdown: return "doc.text"
        case .pdf: return "doc.richtext"
        case .gpx: return "point.topleft.down.to.point.bottomright.curvepath"
        }
    }

    /// Short description of what this format contains.
    var subtitle: String {
        switch self {
        case .markdown: return "Stats, waypoints, and comments as text"
        case .pdf: return "Map, elevation chart, photos, and full stats"
        case .gpx: return "GPS track compatible with all hiking apps"
        }
    }

    /// File extension for the exported file.
    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .pdf: return "pdf"
        case .gpx: return "gpx"
        }
    }

    /// MIME type for share sheet.
    var mimeType: String {
        switch self {
        case .markdown: return "text/markdown"
        case .pdf: return "application/pdf"
        case .gpx: return "application/gpx+xml"
        }
    }
}

/// A sheet presenting export format options with progress and share functionality.
///
/// Displays a format picker, generates the selected export format, shows progress
/// during generation, and presents a share sheet for the result.
///
/// ## Integration
/// Presented from ``HikeDetailView`` via the Export toolbar button.
///
/// ## Export Flow
/// 1. User selects a format
/// 2. Tap "Export" to begin generation
/// 3. Progress indicator shown during async generation
/// 4. Share sheet presented with the generated file
struct ExportSheet: View {
    /// The saved route to export.
    let route: SavedRoute

    /// Waypoints linked to this hike.
    let waypoints: [Waypoint]

    /// Dismiss action for the sheet.
    @Environment(\.dismiss) private var dismiss

    /// User preference for metric (true) or imperial (false) units.
    @AppStorage("useMetricUnits") private var useMetricUnits = true

    /// The currently selected export format.
    @State private var selectedFormat: ExportFormat = .markdown

    /// Whether export is currently in progress.
    @State private var isExporting = false

    /// The generated export data (nil until export completes).
    @State private var exportedFileURL: URL?

    /// Whether the share sheet is presented.
    @State private var showShareSheet = false

    /// Error message to display if export fails.
    @State private var errorMessage: String?

    /// Whether the error alert is shown.
    @State private var showError = false

    /// Preview text for Markdown format.
    @State private var markdownPreview: String = ""

    var body: some View {
        NavigationStack {
            Form {
                // Format picker
                Section {
                    ForEach(ExportFormat.allCases) { format in
                        Button {
                            selectedFormat = format
                        } label: {
                            HStack {
                                Image(systemName: format.iconName)
                                    .foregroundStyle(.blue)
                                    .frame(width: 24)

                                VStack(alignment: .leading) {
                                    Text(format.rawValue)
                                        .foregroundStyle(.primary)
                                    Text(format.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if format == selectedFormat {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Export Format")
                }

                // Preview for Markdown
                if selectedFormat == .markdown && !markdownPreview.isEmpty {
                    Section {
                        ScrollView {
                            Text(markdownPreview)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 200)
                    } header: {
                        Text("Preview")
                    }
                }

                // Export button
                Section {
                    Button {
                        Task {
                            await performExport()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if isExporting {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("Generating...")
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                Text("Export & Share")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isExporting)
                }
            }
            .navigationTitle("Export Hike")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                generatePreview()
            }
            .onChange(of: selectedFormat) {
                generatePreview()
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportedFileURL {
                    ShareSheetView(items: [url])
                }
            }
            .alert("Export Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
        }
    }

    // MARK: - Export Logic

    /// Generates a Markdown preview for the preview section.
    private func generatePreview() {
        if selectedFormat == .markdown {
            markdownPreview = HikeSummaryExporter.toMarkdown(
                route: route,
                waypoints: waypoints,
                useMetric: useMetricUnits
            )
        } else {
            markdownPreview = ""
        }
    }

    /// Performs the export for the selected format.
    ///
    /// Writes the generated data to a temporary file and presents the share sheet.
    /// Errors are caught, logged, and displayed to the user via an alert.
    @MainActor
    private func performExport() async {
        isExporting = true
        defer { isExporting = false }

        do {
            let data: Data
            let filename: String

            switch selectedFormat {
            case .markdown:
                let markdown = HikeSummaryExporter.toMarkdown(
                    route: route,
                    waypoints: waypoints,
                    useMetric: useMetricUnits
                )
                data = Data(markdown.utf8)
                filename = "\(sanitizeFilename(route.name)).\(selectedFormat.fileExtension)"

            case .pdf:
                data = try await PDFExporter.exportAsPDF(
                    route: route,
                    waypoints: waypoints,
                    useMetric: useMetricUnits
                )
                filename = "\(sanitizeFilename(route.name)).\(selectedFormat.fileExtension)"

            case .gpx:
                data = HikeSummaryExporter.toGPX(
                    route: route,
                    waypoints: waypoints
                )
                filename = "\(sanitizeFilename(route.name)).\(selectedFormat.fileExtension)"
            }

            // Write to temp file for sharing
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent(filename)
            try data.write(to: fileURL, options: .atomic)

            exportedFileURL = fileURL
            showShareSheet = true

        } catch {
            errorMessage = error.localizedDescription
            showError = true
            print("Export error: \(error.localizedDescription)")
        }
    }

    /// Sanitizes a route name for use as a filename.
    ///
    /// Replaces characters that are invalid in filenames with hyphens.
    ///
    /// - Parameter name: The route name to sanitize.
    /// - Returns: A filename-safe string.
    private func sanitizeFilename(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let sanitized = name.unicodeScalars
            .map { invalidChars.contains($0) ? "-" : String($0) }
            .joined()
        return sanitized.isEmpty ? "hike-export" : sanitized
    }
}

// MARK: - Share Sheet (UIActivityViewController wrapper)

/// A UIKit wrapper for `UIActivityViewController` usable in SwiftUI.
///
/// Presents the system share sheet with the given items. Used by ``ExportSheet``
/// to share generated export files via Messages, Mail, AirDrop, Files, etc.
struct ShareSheetView: UIViewControllerRepresentable {
    /// The items to share (typically file URLs).
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
