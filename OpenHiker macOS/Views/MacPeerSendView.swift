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

/// macOS sheet view for sending a downloaded region to an iPhone via MultipeerConnectivity.
///
/// Presented from the context menu on a region row in ``MacRegionsListView``.
/// Starts advertising immediately on appear and shows a progress indicator
/// while the transfer is in progress. Automatically stops advertising on disappear.
///
/// ## Flow
/// 1. Sheet opens → starts advertising on local network.
/// 2. iPhone user opens "Receive from Mac" and taps this Mac's name.
/// 3. Connection established → transfer begins automatically.
/// 4. Progress bar shows file transfer progress.
/// 5. Transfer completes → success checkmark shown.
struct MacPeerSendView: View {
    /// The region to send to the iPhone.
    let region: Region

    /// Environment action to dismiss the sheet.
    @Environment(\.dismiss) private var dismiss

    /// The shared peer transfer service that manages the MPC session.
    @ObservedObject private var peerService = PeerTransferService.shared

    var body: some View {
        VStack(spacing: 20) {
            // Header
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Send to iPhone")
                .font(.title2)
                .fontWeight(.semibold)

            Text(region.name)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(region.fileSizeFormatted)
                .font(.caption)
                .foregroundStyle(.tertiary)

            Divider()

            // Status
            statusView

            Spacer()

            // Actions
            HStack {
                Button("Cancel") {
                    peerService.disconnect()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                if case .completed = peerService.transferState {
                    Button("Done") {
                        peerService.disconnect()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(30)
        .frame(width: 360, height: 380)
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
                Text("Waiting for iPhone…")
                    .foregroundStyle(.secondary)
                Text("Open \"Receive from Mac\" on your iPhone")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

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
            VStack(spacing: 12) {
                ProgressView(value: peerService.progress)
                    .progressViewStyle(.linear)
                Text(peerService.transferState.description)
                    .foregroundStyle(.secondary)
                Text("\(Int(peerService.progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

        case .completed:
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
                Text("Transfer Complete")
                    .font(.headline)
                    .foregroundStyle(.green)
            }

        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.red)
                Text("Transfer Failed")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

        case .idle:
            EmptyView()
        }
    }
}
