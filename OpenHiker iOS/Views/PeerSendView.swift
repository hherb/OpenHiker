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

/// iOS sheet view for sending a downloaded region to another device via MultipeerConnectivity.
///
/// Presented from a context menu on a region row in ``RegionsListView``.
/// Starts advertising immediately on appear and shows a progress indicator
/// while the transfer is in progress. Automatically stops advertising on disappear.
///
/// ## Flow
/// 1. Sheet opens → starts advertising on local network.
/// 2. Receiving device opens "Receive" and taps this device's name.
/// 3. Connection established → transfer begins automatically.
/// 4. Progress bar shows file transfer progress.
/// 5. Transfer completes → success checkmark shown.
struct PeerSendView: View {
    /// The region to send to the receiving device.
    let region: Region

    /// Environment action to dismiss the sheet.
    @Environment(\.dismiss) private var dismiss

    /// The shared peer transfer service that manages the MPC session.
    @ObservedObject private var peerService = PeerTransferService.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Header icon
                Image(systemName: "arrow.up.doc")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                    .padding(.top, 20)

                Text(region.name)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text(region.fileSizeFormatted)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Divider()
                    .padding(.horizontal)

                // Status
                statusView

                Spacer()
            }
            .navigationTitle("Share Region")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        peerService.disconnect()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if case .completed = peerService.transferState {
                        Button("Done") {
                            peerService.disconnect()
                            dismiss()
                        }
                    }
                }
            }
        }
        .onAppear {
            peerService.startAdvertising(region: region)
        }
        .onDisappear {
            peerService.stopAdvertising()
        }
    }

    /// The status section showing the current transfer state and progress.
    @ViewBuilder
    private var statusView: some View {
        switch peerService.transferState {
        case .waitingForPeer:
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Waiting for connection…")
                    .foregroundStyle(.secondary)
                Text("The receiving device should tap \"Receive\" and select this phone.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if let vpnWarning = peerService.vpnWarning {
                    Label(vpnWarning, systemImage: "exclamationmark.shield.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.top, 4)
                }
            }
            .padding()

        case .connected:
            VStack(spacing: 12) {
                Image(systemName: "link.circle.fill")
                    .font(.title)
                    .foregroundStyle(.green)
                Text("Connected — starting transfer…")
                    .foregroundStyle(.secondary)
            }

        case .sendingManifest, .sendingMBTiles, .sendingRouting,
             .sendingSavedRoutes, .sendingPlannedRoutes, .sendingWaypoints:
            VStack(spacing: 16) {
                ProgressView(value: peerService.progress)
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 40)

                Text(peerService.transferState.description)
                    .foregroundStyle(.secondary)

                Text("\(Int(peerService.progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .padding()

        case .completed:
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("Transfer Complete")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text("Region and associated routes have been sent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()

        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
                Text("Transfer Failed")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button("Try Again") {
                    peerService.disconnect()
                    peerService.startAdvertising(region: region)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
            .padding()

        case .idle:
            EmptyView()
        }
    }
}
