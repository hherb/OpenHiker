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

/// macOS-specific menu commands for the OpenHiker app.
///
/// Adds custom commands to the macOS menu bar:
/// - **File > Sync with iCloud** (Cmd+Shift+S): Triggers a manual iCloud sync
///
/// These commands integrate with the macOS system menu bar and follow
/// Apple's Human Interface Guidelines for macOS command naming.
struct OpenHikerCommands: Commands {

    var body: some Commands {
        // Add to the existing File menu
        CommandGroup(after: .saveItem) {
            Button("Sync with iCloud") {
                Task {
                    await CloudSyncManager.shared.performSync()
                }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }
    }
}
