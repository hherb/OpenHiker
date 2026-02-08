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

// MARK: - UV Category

/// WHO/WMO UV index exposure categories with associated colours and protection advice.
///
/// Categories follow the internationally recognized UV index scale:
/// - Low (0-2): No protection required
/// - Moderate (3-5): Protection recommended
/// - High (6-7): Protection essential
/// - Very High (8-10): Extra protection essential
/// - Extreme (11+): Stay indoors if possible
///
/// Shared across iOS, watchOS, and macOS targets.
enum UVCategory: String, Equatable {
    case low = "Low"
    case moderate = "Moderate"
    case high = "High"
    case veryHigh = "Very High"
    case extreme = "Extreme"

    /// Maps a numeric UV index to its WHO/WMO category.
    ///
    /// - Parameter index: The UV index value (0-11+).
    /// - Returns: The corresponding ``UVCategory``.
    static func from(index: Int) -> UVCategory {
        switch index {
        case 0...2: return .low
        case 3...5: return .moderate
        case 6...7: return .high
        case 8...10: return .veryHigh
        default: return .extreme
        }
    }

    /// The recommended display color for this UV category.
    ///
    /// Colors follow the standard WHO UV index color scheme:
    /// - Low: Green
    /// - Moderate: Yellow
    /// - High: Orange
    /// - Very High: Red
    /// - Extreme: Violet/Purple
    var displayColor: Color {
        switch self {
        case .low: return .green
        case .moderate: return .yellow
        case .high: return .orange
        case .veryHigh: return .red
        case .extreme: return .purple
        }
    }

    /// A brief sun protection recommendation for this UV category.
    var protectionAdvice: String {
        switch self {
        case .low:
            return "No protection needed"
        case .moderate:
            return "Wear sunscreen"
        case .high:
            return "Reduce sun exposure"
        case .veryHigh:
            return "Avoid midday sun"
        case .extreme:
            return "Stay in shade"
        }
    }
}
