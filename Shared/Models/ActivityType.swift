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

/// The type of outdoor activity a route was recorded during.
///
/// Used to categorize shared routes in the community repository for filtering
/// and display. The raw value is persisted as a string in JSON, so new cases
/// can be added without breaking existing data.
enum ActivityType: String, Codable, CaseIterable, Sendable {
    /// A hiking or walking activity on trails or footpaths.
    case hiking
    /// A cycling activity (road, gravel, or mountain biking).
    case cycling
    /// A running or trail running activity.
    case running
    /// A ski touring or backcountry skiing activity.
    case skiTouring
    /// Any other outdoor activity not covered by the above categories.
    case other

    /// SF Symbol name for this activity type, used in UI pickers and list rows.
    var iconName: String {
        switch self {
        case .hiking:    return "figure.hiking"
        case .cycling:   return "figure.outdoor.cycle"
        case .running:   return "figure.run"
        case .skiTouring: return "figure.skiing.downhill"
        case .other:     return "figure.walk"
        }
    }

    /// A short human-readable label suitable for display in pickers and filters.
    var displayName: String {
        switch self {
        case .hiking:    return "Hiking"
        case .cycling:   return "Cycling"
        case .running:   return "Running"
        case .skiTouring: return "Ski Touring"
        case .other:     return "Other"
        }
    }
}
