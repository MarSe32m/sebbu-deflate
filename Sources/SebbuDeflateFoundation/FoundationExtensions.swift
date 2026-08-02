#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@_exported import SebbuDeflate

public extension DeflateCompressor {
    /// Compresses a data buffer.
    ///
    /// This method allocates a new `Data` value with enough capacity for the
    /// worst-case compressed size and returns only the bytes initialized by
    /// the compression operation.
    ///
    /// Reuse this compressor for repeated compression operations to avoid
    /// repeatedly allocating the underlying libdeflate compressor.
    ///
    /// - Parameters:
    ///   - format: The container format to produce. The default is zlib.
    ///   - input: The data to compress.
    /// - Returns: The compressed representation of `input`.
    /// - Throws: A ``DeflateError`` if compression fails.
    func compress(
        format: DeflateCompressionFormat = .zlib,
        bytes input: Data
    ) throws(DeflateError) -> Data {
        #if swift(<6.4)
        return try Data(compress(format: format, bytes: [UInt8](input)))
        #else
        let bound = compressedByteCountBound(format: format, byteCount: input.count)
        return try Data(rawCapacity: bound) { (output: inout OutputRawSpan) throws(DeflateError) -> Void in 
            try compress(format: format, bytes: input.bytes, into: &output)
        }
        #endif
    }

    /// Compresses a data buffer using a temporary compressor.
    ///
    /// This method allocates the output data automatically. For repeated
    /// compression operations, create and reuse a ``DeflateCompressor``
    /// instance instead.
    ///
    /// - Parameters:
    ///   - format: The container format to produce. The default is zlib.
    ///   - level: The compression level to use. The default is balanced.
    ///   - input: The data to compress.
    /// - Returns: The compressed representation of `input`.
    /// - Throws: A ``DeflateError`` if compression fails.
    static func compress(
        format: DeflateCompressionFormat = .zlib,
        level: DeflateCompressionLevel = .balanced,
        bytes input: Data
    ) throws(DeflateError) -> Data {
        let compressor = DeflateCompressor(level: level)
        return try compressor.compress(format: format, bytes: input)
    }
}

public extension DeflateDecompressor {
    /// Decompresses a data buffer into a new value of a known size.
    ///
    /// `exactSize` is the exact expected output size, not an upper
    /// bound. The operation succeeds only if `input` decompresses to exactly
    /// that number of bytes.
    ///
    /// This method decompresses only the first stream contained in `input`.
    /// In particular, concatenated gzip members are not decompressed
    /// automatically.
    ///
    /// - Parameters:
    ///   - format: The format of the compressed data. The default is zlib.
    ///   - input: The compressed data.
    ///   - exactSize: The exact expected number of uncompressed bytes.
    /// - Returns: A data buffer containing exactly `exactSize`
    ///   uncompressed bytes.
    /// - Throws:
    ///   - ``DeflateError/badData`` if `input` is not valid compressed data
    ///     in `format`.
    ///   - ``DeflateError/shortOutput`` if the uncompressed data is smaller
    ///     than `exactSize`.
    ///   - ``DeflateError/insufficientSpace`` if the uncompressed data is
    ///     larger than `exactSize`.
    /// - Precondition: `exactSize` is nonnegative.
    func decompress(
        format: DeflateCompressionFormat = .zlib,
        bytes input: Data,
        exactSize: Int
    ) throws(DeflateError) -> Data {
        precondition(exactSize >= 0)
        var output = Data(count: exactSize)
        var mutableSpan = output.mutableSpan
        try decompress(format: format, bytes: input.span, into: &mutableSpan)
        return output
    }

    /// Decompresses a data buffer with a known uncompressed size using a
    /// temporary decompressor.
    ///
    /// The operation succeeds only if the decompressed byte count equals
    /// `exactSize`. For repeated decompression operations, create and
    /// reuse a ``DeflateDecompressor`` instance instead.
    ///
    /// - Parameters:
    ///   - format: The format of the compressed data. The default is zlib.
    ///   - input: The compressed data.
    ///   - exactSize: The exact expected number of uncompressed bytes.
    /// - Returns: The uncompressed data.
    /// - Throws:
    ///   - ``DeflateError/badData`` if `input` is invalid, corrupt, or
    ///     unsupported.
    ///   - ``DeflateError/shortOutput`` if the uncompressed data is smaller
    ///     than `exactSize`.
    ///   - ``DeflateError/insufficientSpace`` if the uncompressed data is
    ///     larger than `exactSize`.
    /// - Precondition: `exactSize` is nonnegative.
    @inlinable
    static func decompress(
        format: DeflateCompressionFormat = .zlib,
        bytes input: Data,
        exactSize: Int
    ) throws(DeflateError) -> Data {
        let decompressor = DeflateDecompressor()
        return try decompressor.decompress(format: format, bytes: input, exactSize: exactSize)
    }

    /// Decompresses a data buffer into a new value with a maximum uncompressed size.
    ///
    /// This method decompresses only the first stream contained in `input`.
    /// In particular, concatenated gzip members are not decompressed
    /// automatically.
    ///
    /// - Parameters:
    ///   - format: The format of the compressed data. The default is zlib.
    ///   - input: The compressed data.
    ///   - maximumSize: The maximum expected number of uncompressed bytes.
    /// - Returns: A data buffer containing the uncompressed bytes.
    /// - Throws:
    ///   - ``DeflateError/badData`` if `input` is not valid compressed data
    ///     in `format`.
    ///   - ``DeflateError/insufficientSpace`` if the uncompressed data is
    ///     larger than `maximumSize`.
    /// - Precondition: `maximumSize` is nonnegative.
    func decompress(
        format: DeflateCompressionFormat = .zlib,
        bytes input: Data,
        maximumSize: Int
    ) throws(DeflateError) -> Data {
        precondition(maximumSize >= 0)
        #if swift(<6.4)
        return try .init(decompress(format: format, bytes: [UInt8](input), maximumSize: maximumSize))
        #else
        return try .init(rawCapacity: maximumSize) { (output: inout OutputRawSpan) throws(DeflateError) -> Void in 
            try decompress(format: format, bytes: input.bytes, into: &output)
        }
        #endif
    }

    /// Decompresses a data buffer with a maximum uncompressed size using a
    /// temporary decompressor.
    /// 
    /// For repeated decompression operations, create and
    /// reuse a ``DeflateDecompressor`` instance instead.
    ///
    /// - Parameters:
    ///   - format: The format of the compressed data. The default is zlib.
    ///   - input: The compressed data.
    ///   - maximumSize: The exact expected number of uncompressed bytes.
    /// - Returns: The uncompressed data.
    /// - Throws:
    ///   - ``DeflateError/badData`` if `input` is invalid, corrupt, or
    ///     unsupported.
    ///   - ``DeflateError/insufficientSpace`` if the uncompressed data is
    ///     larger than `maximumSize`.
    /// - Precondition: `maximumSize` is nonnegative.
    @inlinable
    static func decompress(
        format: DeflateCompressionFormat = .zlib,
        bytes input: Data,
        maximumSize: Int
    ) throws(DeflateError) -> Data {
        let decompressor = DeflateDecompressor()
        return try decompressor.decompress(format: format, bytes: input, maximumSize: maximumSize)
    }
}