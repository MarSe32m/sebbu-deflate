// Copyright (c) 2026 Sebastian Toivonen
// SPDX-License-Identifier: MIT

/// A format used to encode DEFLATE-compressed data.
///
/// All supported formats use the DEFLATE compression algorithm. They differ in
/// how the compressed bitstream is framed and which integrity information is
/// included.
public enum DeflateCompressionFormat: Sendable, CaseIterable {
    /// A raw DEFLATE bitstream.
    ///
    /// This format contains no zlib or gzip header, trailer or checksum. Use it
    /// when the surrounding protocol provides its own framing or explicitly
    /// requires raw DEFLATE data.
    case raw

    /// A DEFLATE bitstream wrapped in the zlib format.
    ///
    /// The zlib wrapper includes a header and an Adler-32 checksum of the
    /// uncompressed data.
    case zlib

    /// A DEFLATE bitstream wrapped in the gzip format.
    ///
    /// The gzip wrapper includes a header and a trailer containing a CRC-32
    /// checksum and the uncompressed input size.
    case gzip
}