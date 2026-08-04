// Copyright (c) 2026 Sebastian Toivonen
// SPDX-License-Identifier: MIT

/// A compression level used by libdeflate.
///
/// Valid compression levels range from `0` through `12`. Level `0` emits
/// uncompressed DEFLATE blocks. Levels `1` through `12` trade compression speed
/// for output size: higher levels generally compress more slowly but produce
/// smaller output.
public struct DeflateCompressionLevel: RawRepresentable, Sendable {
    /// The numeric libdeflate compression level.
    public let rawValue: Int32

    /// Disables compression while retaining the selected DEFLATE container format (`0`).
    public static let noCompression = Self(rawValue: 0)!

    /// The fastest level that performs compression (`1`).
    public static let fastest = Self(rawValue: 1)!

    /// A balanced compression level (`6`).
    ///
    /// This level provides a compromise between compression speed and output
    /// size and is the default used by ``DeflateCompressor``.
    public static let balanced = Self(rawValue: 6)!

    /// The highest supported compression level (`12`).
    ///
    /// This level prioritizes compressed output size over compression speed.
    public static let best = Self(rawValue: 12)!

    /// Creates a compression level from its 32-bit integer representation.
    ///
    /// - Parameter rawValue: A compression level in the range `0...12`.
    /// - Returns: `nil` if `rawValue` is outside the supported range.
    public init?(rawValue: Int32) {
        guard (0...12).contains(rawValue) else {
            return nil
        }
        self.rawValue = rawValue
    }

    /// Creates a compression level from an integer.
    ///
    /// - Parameter rawValue: A compression level in the range `0...12`.
    /// - Returns: `nil` if `rawValue` is outside the supported range.
    public init?(rawValue: Int) {
        guard (0...12).contains(rawValue) else {
            return nil
        }
        self.init(rawValue: Int32(rawValue))
    }
}