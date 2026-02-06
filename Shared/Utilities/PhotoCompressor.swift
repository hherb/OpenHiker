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

#if canImport(UIKit)
import UIKit
#endif
import Foundation

/// Compresses and downsamples photos for upload to the community route repository.
///
/// Photos are resized to fit within a maximum dimension (640x400 by default) and
/// compressed as JPEG at 70% quality. This keeps each photo around 30-80 KB,
/// making the repository viable even with thousands of routes containing photos.
///
/// ## Thread Safety
/// All methods are pure static functions with no shared state, safe to call from any thread.
enum PhotoCompressor {

    /// Maximum width in pixels for compressed photos.
    static let maxWidth: CGFloat = 640

    /// Maximum height in pixels for compressed photos.
    static let maxHeight: CGFloat = 400

    /// JPEG compression quality (0.0 = maximum compression, 1.0 = maximum quality).
    ///
    /// 0.7 provides a good balance between file size and visual clarity for
    /// on-screen viewing at phone resolution.
    static let jpegQuality: CGFloat = 0.7

    #if canImport(UIKit)
    /// Compresses a UIImage to a JPEG suitable for community route sharing.
    ///
    /// The image is downsampled to fit within ``maxWidth`` x ``maxHeight`` pixels
    /// while preserving its aspect ratio, then encoded as JPEG at ``jpegQuality``.
    ///
    /// - Parameter image: The source image to compress.
    /// - Returns: JPEG data of the compressed image, or `nil` if encoding fails.
    static func compress(_ image: UIImage) -> Data? {
        let resized = downsample(image, maxWidth: maxWidth, maxHeight: maxHeight)
        return resized.jpegData(compressionQuality: jpegQuality)
    }

    /// Compresses raw image data (PNG or JPEG) to a compressed JPEG.
    ///
    /// First creates a UIImage from the raw data, then applies ``compress(_:)``.
    ///
    /// - Parameter data: The raw image data (PNG, JPEG, or any format UIImage supports).
    /// - Returns: JPEG data of the compressed image, or `nil` if the data is not a valid image.
    static func compressData(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return compress(image)
    }

    /// Downsamples an image to fit within the given maximum dimensions.
    ///
    /// If the image already fits within the target size, it is returned unchanged.
    /// The aspect ratio is always preserved — the image is scaled to fit, not fill.
    ///
    /// - Parameters:
    ///   - image: The source image to resize.
    ///   - maxWidth: Maximum width in pixels.
    ///   - maxHeight: Maximum height in pixels.
    /// - Returns: The resized image, or the original if no resizing was needed.
    static func downsample(_ image: UIImage, maxWidth: CGFloat, maxHeight: CGFloat) -> UIImage {
        let size = image.size

        // Already within bounds
        if size.width <= maxWidth && size.height <= maxHeight {
            return image
        }

        // Calculate scale factor preserving aspect ratio
        let widthRatio = maxWidth / size.width
        let heightRatio = maxHeight / size.height
        let scale = min(widthRatio, heightRatio)

        let newSize = CGSize(
            width: floor(size.width * scale),
            height: floor(size.height * scale)
        )

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    #endif
}
