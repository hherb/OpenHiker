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

/// A reusable sheet for renaming items on watchOS.
///
/// Presents a text field pre-filled with the current name and Save/Cancel buttons.
/// Used by ``RegionsListView`` and ``WatchPlannedRoutesView`` to rename regions
/// and planned routes respectively.
///
/// ## Usage
/// ```swift
/// .sheet(isPresented: $showRename) {
///     RenameSheet(title: "Rename Region", name: $renameText) { newName in
///         // persist newName
///     }
/// }
/// ```
struct RenameSheet: View {
    /// Title displayed at the top of the sheet (e.g. "Rename Region").
    let title: String

    /// Binding to the editable name text.
    @Binding var name: String

    /// Callback invoked with the trimmed new name when the user taps Save.
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)

            TextField("Name", text: $name)

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Button("Save") {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    onSave(trimmed)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
    }
}
