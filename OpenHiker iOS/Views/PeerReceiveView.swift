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

/// iOS sheet view for receiving a downloaded region from a Mac via MultipeerConnectivity.
///
/// Presented from a toolbar button on the ``RegionsListView`` (Downloaded Regions tab).
/// Starts browsing for nearby Macs immediately on appear and shows discovered peers
/// in a list. Tapping a peer sends an invitation, after which the transfer begins
/// automatically.
///
/// ## Flow
/// 1. Sheet opens → starts browsing for nearby Macs.
/// 2. Discovered Macs appear in a list with their names.
/// 3. User taps a Mac → invitation sent → connection established.
/// 4. Mac begins sending region files automatically.
/// 5. Progress bar shows file transfer progress.
/// 6. Transfer completes → region appears in Downloaded Regions.
struct PeerReceiveView: View {
    /// Environment action to dismiss the sheet.
    @Environment(\.dismiss) private var dismiss

    /// The shared peer transfer service that manages the MPC session.
    @ObservedObject private var peerService = PeerTransferService.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Header icon
                Image(systemName: "laptopcomputer.and.arrow.down")
                    .font(.system(size: 44))
                    .foregroundStyle(.blue)
                    .padding(.top, 20)

                // Content based on state
                contentView

                Spacer()
            }
            .navigationTitle("Receive from Mac")
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
            peerService.startBrowsing()
        }
        .onDisappear {
            peerService.stopBrowsing()
        }
    }

    /// The main content area, which changes based on the current transfer state.
    @ViewBuilder
    private var contentView: some View {
        switch peerService.transferState {
        case .waitingForPeer:
            peerListView

        case .connected:
            VStack(spacing: 12) {
                Image(systemName: "link.circle.fill")
                    .font(.title)
                    .foregroundStyle(.green)
                Text("Connected — waiting for transfer…")
                    .foregroundStyle(.secondary)
            }
            .padding()

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
                Text("Region and associated routes have been imported.")
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
                    peerService.startBrowsing()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
            .padding()

        case .idle:
            EmptyView()
        }
    }

    /// Displays a list of discovered Mac peers, or a scanning indicator if none found yet.
    @ViewBuilder
    private var peerListView: some View {
        if peerService.discoveredPeers.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("Scanning for nearby Macs…")
                    .foregroundStyle(.secondary)
                Text("Make sure \"Send to iPhone\" is open on your Mac.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
        } else {
            List {
                Section("Available Macs") {
                    ForEach(peerService.discoveredPeers, id: \.self) { peer in
                        Button {
                            peerService.invitePeer(peer)
                        } label: {
                            HStack {
                                Image(systemName: "desktopcomputer")
                                    .foregroundStyle(.blue)
                                Text(peer.displayName)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}
