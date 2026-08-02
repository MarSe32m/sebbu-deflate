import CLibDeflate

/// A reusable whole-buffer decompressor for raw DEFLATE, zlib and gzip data.
///
/// Each call decompresses an independent compressed stream. The decompressor
/// does not retain streaming state between calls and can decompress data
/// produced at any compression level.
///
/// Use an `OutputRawSpan` or `OutputSpan<UInt8>` when the exact uncompressed
/// size is unknown and the output capacity is only an upper bound. Use a
/// `MutableRawSpan` or `MutableSpan<UInt8>` when the uncompressed size is known
/// exactly.
///
/// Reusing a decompressor avoids repeatedly allocating the underlying
/// libdeflate decompressor. A single instance must not be used by overlapping
/// decompression operations. Create a separate decompressor for each
/// concurrently executing task or thread.
///
/// These methods decompress only the first stream contained in the input. In
/// particular, concatenated gzip members are not decompressed automatically.
public struct DeflateDecompressor: ~Copyable {
    @usableFromInline
    internal let decompressor: OpaquePointer

    /// Creates a reusable decompressor.
    ///
    /// The resulting decompressor supports raw DEFLATE, zlib and gzip data
    /// produced at any compression level.
    @inlinable
    public init() {
        // The default libdeflate_alloc_decompressor() returns NULL only when running out of memory
        guard let decompressor = libdeflate_alloc_decompressor() else {
            preconditionFailure("Couldn't allocate new decompressor due to running out of memory")
        }
        self.decompressor = decompressor
    }

    /// Decompresses raw bytes when their exact uncompressed size is unknown.
    ///
    /// The free capacity of `output` is treated as the maximum permitted
    /// uncompressed size. On success, the initialized region of `output` is
    /// extended by the actual number of bytes decompressed.
    ///
    /// - Parameters:
    ///   - format: The format of the compressed data. The default is zlib.
    ///   - input: The compressed bytes.
    ///   - output: Storage for the uncompressed bytes.
    /// - Throws:
    ///   - ``DeflateError/badData`` if `input` is invalid, corrupt or
    ///     unsupported.
    ///   - ``DeflateError/insufficientSpace`` if the uncompressed data does not
    ///     fit in the free capacity of `output`.
    @inlinable
    public func decompress(
        format: DeflateCompressionFormat = .zlib,
        bytes input: RawSpan, 
        into output: inout OutputRawSpan
    ) throws(DeflateError) {
        let result = input.withUnsafeBytes { input in 
            output.withUnsafeMutableBytes { output, initializedCount in 
                let output = 
                    UnsafeMutableRawBufferPointer(
                        start: output.baseAddress?.advanced(by: initializedCount), 
                        count: output.count - initializedCount
                    )
                var actualBytes = 0
                let result = _decompress(format: format, bytes: input, into: output, actualBytes: &actualBytes)
                //TODO: Is this check unnecessary? The docs say that actualBytes are written to only in case of success
                if result == LIBDEFLATE_SUCCESS {
                    // Only increase the initializedCount on success
                    initializedCount += actualBytes
                }
                return result
            }
        }
        switch result {
            case LIBDEFLATE_SUCCESS:
                break
            case LIBDEFLATE_BAD_DATA:
                throw .badData
            case LIBDEFLATE_SHORT_OUTPUT:
                throw .shortOutput
            case LIBDEFLATE_INSUFFICIENT_SPACE:
                throw .insufficientSpace
            default: fatalError("Unreachable")
        }
    }

    /// Decompresses a span of bytes when its exact uncompressed size is unknown.
    ///
    /// The free capacity of `output` is treated as the maximum permitted
    /// uncompressed size. On success, the initialized region of `output` is
    /// extended by the actual number of bytes decompressed.
    ///
    /// - Parameters:
    ///   - format: The format of the compressed data. The default is zlib.
    ///   - input: The compressed bytes.
    ///   - output: Storage for the uncompressed bytes.
    /// - Throws:
    ///   - ``DeflateError/badData`` if `input` is invalid, corrupt or
    ///     unsupported.
    ///   - ``DeflateError/insufficientSpace`` if the uncompressed data does not
    ///     fit in the free capacity of `output`.
    @inlinable
    public func decompress(
        format: DeflateCompressionFormat = .zlib,
        bytes input: Span<UInt8>,
        into output: inout OutputSpan<UInt8>
    ) throws(DeflateError) {
        let result = input.withUnsafeBufferPointer { input in 
            output.withUnsafeMutableBufferPointer { output, initializedCount in
                let output = 
                    UnsafeMutableBufferPointer<UInt8>(
                        start: output.baseAddress?.advanced(by: initializedCount), 
                        count: output.count - initializedCount
                    )
                var actualBytes = 0
                let result = _decompress(format: format, bytes: input, into: output, actualBytes: &actualBytes)
                //TODO: Is this check unnecessary? The docs say that actualBytes are written to only in case of success
                if result == LIBDEFLATE_SUCCESS {
                    // Only increase the initializedCount on success
                    initializedCount += actualBytes
                }
                return result
            }
        }
        switch result {
            case LIBDEFLATE_SUCCESS:
                break
            case LIBDEFLATE_BAD_DATA:
                throw .badData
            case LIBDEFLATE_SHORT_OUTPUT:
                throw .shortOutput
            case LIBDEFLATE_INSUFFICIENT_SPACE:
                throw .insufficientSpace
            default: fatalError("Unreachable")
        }
    }

    /// Decompresses raw bytes with a known uncompressed size.
    ///
    /// The size of `output` is treated as the exact expected uncompressed size.
    /// Decompression succeeds only if the operation fills the entire span.
    ///
    /// - Parameters:
    ///   - format: The format of the compressed data. The default is zlib.
    ///   - input: The compressed bytes.
    ///   - output: A span whose size equals the expected uncompressed size.
    /// - Throws:
    ///   - ``DeflateError/badData`` if `input` is invalid, corrupt, or
    ///     unsupported.
    ///   - ``DeflateError/shortOutput`` if the uncompressed data is smaller
    ///     than `output`.
    ///   - ``DeflateError/insufficientSpace`` if the uncompressed data is
    ///     larger than `output`.
    /// - Important: If decompression fails, the contents of `output` are
    ///   undefined and may have been partially overwritten.
    @inlinable
    public func decompress(
        format: DeflateCompressionFormat = .zlib,
        bytes input: RawSpan, 
        into output: inout MutableRawSpan
    ) throws(DeflateError) {
        let result = input.withUnsafeBytes { input in 
            output.withUnsafeMutableBytes { output in 
                _decompress(format: format, bytes: input, into: output, actualBytes: nil)
            }
        }
        switch result {
            case LIBDEFLATE_SUCCESS:
                break
            case LIBDEFLATE_BAD_DATA:
                throw .badData
            case LIBDEFLATE_SHORT_OUTPUT:
                throw .shortOutput
            case LIBDEFLATE_INSUFFICIENT_SPACE:
                throw .insufficientSpace
            default: fatalError("Unreachable")
        }
    }

    /// Decompresses a span of bytes with a known uncompressed size.
    ///
    /// The size of `output` is treated as the exact expected uncompressed size.
    /// Decompression succeeds only if the operation fills the entire span.
    ///
    /// - Parameters:
    ///   - format: The format of the compressed data. The default is zlib.
    ///   - input: The compressed bytes.
    ///   - output: A span whose size equals the expected uncompressed size.
    /// - Throws:
    ///   - ``DeflateError/badData`` if `input` is invalid, corrupt, or
    ///     unsupported.
    ///   - ``DeflateError/shortOutput`` if the uncompressed data is smaller
    ///     than `output`.
    ///   - ``DeflateError/insufficientSpace`` if the uncompressed data is
    ///     larger than `output`.
    /// - Important: If decompression fails, the contents of `output` are
    ///   undefined and may have been partially overwritten.
    @inlinable
    public func decompress(
        format: DeflateCompressionFormat = .zlib,
        bytes input: Span<UInt8>,
        into output: inout MutableSpan<UInt8>
    ) throws(DeflateError) {
        let result = input.withUnsafeBufferPointer { input in 
            output.withUnsafeMutableBufferPointer { output in
                return _decompress(format: format, bytes: input, into: output, actualBytes: nil)
            }
        }
        switch result {
            case LIBDEFLATE_SUCCESS:
                break
            case LIBDEFLATE_BAD_DATA:
                throw .badData
            case LIBDEFLATE_SHORT_OUTPUT:
                throw .shortOutput
            case LIBDEFLATE_INSUFFICIENT_SPACE:
                throw .insufficientSpace
            default: fatalError("Unreachable")
        }
    }

    /// Decompresses an array of bytes with a known uncompressed size.
    ///
    /// This method allocates the output array automatically and verifies that
    /// its resulting size matches `exactSize`.
    ///
    /// - Parameters:
    ///   - format: The format of the compressed data. The default is zlib.
    ///   - input: The compressed bytes.
    ///   - exactSize: The exact expected number of uncompressed bytes.
    /// - Returns: The uncompressed bytes.
    /// - Throws:
    ///   - ``DeflateError/badData`` if `input` is invalid, corrupt, or
    ///     unsupported.
    ///   - ``DeflateError/shortOutput`` if the uncompressed data is smaller
    ///     than `exactSize`.
    ///   - ``DeflateError/insufficientSpace`` if the uncompressed data is
    ///     larger than `exactSize`.
    /// - Precondition: `exactSize` is nonnegative.
    @inlinable
    public func decompress(
        format: DeflateCompressionFormat = .zlib,
        bytes input: [UInt8],
        exactSize: Int
    ) throws(DeflateError) -> [UInt8] {
        precondition(exactSize >= 0)
        var output: [UInt8] = .init(repeating: .zero, count: exactSize)
        var mutableSpan = output.mutableSpan
        try decompress(format: format, bytes: input.span, into: &mutableSpan)
        return output
    }

    /// Decompresses an array of bytes with a maximum uncompressed size.
    ///
    /// This method allocates the output array automatically.
    ///
    /// - Parameters:
    ///   - format: The format of the compressed data. The default is zlib.
    ///   - input: The compressed bytes.
    ///   - maximumSize: The maximum expected number of uncompressed bytes.
    /// - Returns: The uncompressed bytes.
    /// - Throws:
    ///   - ``DeflateError/badData`` if `input` is invalid, corrupt, or
    ///     unsupported.
    ///   - ``DeflateError/insufficientSpace`` if the uncompressed data is
    ///     larger than `maximumSize`.
    /// - Precondition: `maximumSize` is nonnegative.
    @inlinable
    public func decompress(
        format: DeflateCompressionFormat = .zlib,
        bytes input: [UInt8],
        maximumSize: Int
    ) throws(DeflateError) -> [UInt8] {
        precondition(maximumSize >= 0)
        return try .init(capacity: maximumSize) { (span: inout OutputSpan<UInt8>) throws(DeflateError) -> Void in 
            try decompress(format: format, bytes: input.span, into: &span)
        }
    }

    @inlinable
    internal func _decompress(
        format: DeflateCompressionFormat,
        bytes input: UnsafeRawBufferPointer,
        into output: UnsafeMutableRawBufferPointer,
        actualBytes: UnsafeMutablePointer<Int>?
    ) -> libdeflate_result {
        switch format {
            case .raw:
            libdeflate_deflate_decompress(decompressor, input.baseAddress, input.count, output.baseAddress, output.count, actualBytes)
            case .zlib:
            libdeflate_zlib_decompress(decompressor, input.baseAddress, input.count, output.baseAddress, output.count, actualBytes)
            case .gzip:
            libdeflate_gzip_decompress(decompressor, input.baseAddress, input.count, output.baseAddress, output.count, actualBytes)
        }
    }

    @inlinable
    internal func _decompress(
        format: DeflateCompressionFormat,
        bytes input: UnsafeBufferPointer<UInt8>,
        into output: UnsafeMutableBufferPointer<UInt8>,
        actualBytes: UnsafeMutablePointer<Int>?
    ) -> libdeflate_result {
        switch format {
            case .raw:
            libdeflate_deflate_decompress(decompressor, input.baseAddress, input.count, output.baseAddress, output.count, actualBytes)
            case .zlib:
            libdeflate_zlib_decompress(decompressor, input.baseAddress, input.count, output.baseAddress, output.count, actualBytes)
            case .gzip:
            libdeflate_gzip_decompress(decompressor, input.baseAddress, input.count, output.baseAddress, output.count, actualBytes)
        }
    }

    deinit {
        libdeflate_free_decompressor(decompressor)
    }
}

public extension DeflateDecompressor {
    /// Decompresses raw bytes using a temporary decompressor when the exact
    /// uncompressed size is unknown.
    ///
    /// For repeated operations, create and reuse a ``DeflateDecompressor``
    /// instance instead.
    ///
    /// - Parameters:
    ///   - format: The format of the compressed data. The default is zlib.
    ///   - input: The compressed bytes.
    ///   - output: Storage whose free capacity is the maximum permitted
    ///     uncompressed size.
    /// - Throws: A ``DeflateError`` if the input is invalid or the output has
    ///   insufficient capacity.
    @inlinable
    static func decompress(
        format: DeflateCompressionFormat = .zlib,
        bytes input: RawSpan, 
        into output: inout OutputRawSpan
    ) throws(DeflateError) {
        let decompressor = DeflateDecompressor()
        try decompressor.decompress(format: format, bytes: input, into: &output)
    }

    /// Decompresses a span of bytes using a temporary decompressor when the
    /// exact uncompressed size is unknown.
    ///
    /// For repeated operations, create and reuse a ``DeflateDecompressor``
    /// instance instead.
    ///
    /// - Parameters:
    ///   - format: The format of the compressed data. The default is zlib.
    ///   - input: The compressed bytes.
    ///   - output: Storage whose free capacity is the maximum permitted
    ///     uncompressed size.
    /// - Throws: A ``DeflateError`` if the input is invalid or the output has
    ///   insufficient capacity.
    @inlinable
    static func decompress(
        format: DeflateCompressionFormat = .zlib,
        bytes input: Span<UInt8>,
        into output: inout OutputSpan<UInt8>
    ) throws(DeflateError) {
        let decompressor = DeflateDecompressor()
        try decompressor.decompress(format: format, bytes: input, into: &output)
    }

    /// Decompresses raw bytes with a known uncompressed size using a temporary
    /// decompressor.
    ///
    /// The size of `output` is treated as the exact expected uncompressed size.
    ///
    /// - Parameters:
    ///   - format: The format of the compressed data. The default is zlib.
    ///   - input: The compressed bytes.
    ///   - output: A span whose size equals the expected uncompressed size.
    /// - Throws: A ``DeflateError`` if decompression fails or the decompressed
    ///   size does not equal the size of `output`.
    @inlinable
    static func decompress(
        format: DeflateCompressionFormat = .zlib,
        bytes input: RawSpan, 
        into output: inout MutableRawSpan
    ) throws(DeflateError) {
        let decompressor = DeflateDecompressor()
        try decompressor.decompress(format: format, bytes: input, into: &output)
    }

    /// Decompresses a span of bytes with a known uncompressed size using a
    /// temporary decompressor.
    ///
    /// The size of `output` is treated as the exact expected uncompressed size.
    ///
    /// - Parameters:
    ///   - format: The format of the compressed data. The default is zlib.
    ///   - input: The compressed bytes.
    ///   - output: A span whose size equals the expected uncompressed size.
    /// - Throws: A ``DeflateError`` if decompression fails or the decompressed
    ///   size does not equal the size of `output`.
    @inlinable
    static func decompress(
        format: DeflateCompressionFormat = .zlib,
        bytes input: Span<UInt8>,
        into output: inout MutableSpan<UInt8>
    ) throws(DeflateError) {
        let decompressor = DeflateDecompressor()
        try decompressor.decompress(format: format, bytes: input, into: &output)
    }

    /// Decompresses an array of bytes with a known uncompressed size using a
    /// temporary decompressor.
    ///
    /// - Parameters:
    ///   - format: The format of the compressed data. The default is zlib.
    ///   - input: The compressed bytes.
    ///   - exactSize: The exact expected number of uncompressed bytes.
    /// - Returns: The uncompressed bytes.
    /// - Throws: A ``DeflateError`` if decompression fails or the decompressed
    ///   size does not equal `exactSize`.
    /// - Precondition: `exactSize` is nonnegative.
    @inlinable
    static func decompress(
        format: DeflateCompressionFormat = .zlib,
        bytes input: [UInt8],
        exactSize: Int
    ) throws(DeflateError) -> [UInt8] {
        let decompressor = DeflateDecompressor()
        return try decompressor.decompress(format: format, bytes: input, exactSize: exactSize)
    }

    /// Decompresses an array of bytes with a maximum uncompressed size using a
    /// temporary decompressor.
    ///
    /// - Parameters:
    ///   - format: The format of the compressed data. The default is zlib.
    ///   - input: The compressed bytes.
    ///   - maximumSize: The maximum expected number of uncompressed bytes.
    /// - Returns: The uncompressed bytes.
    /// - Throws: A ``DeflateError`` if decompression fails..
    /// - Precondition: `maximumSize` is nonnegative.
    @inlinable
    static func decompress(
        format: DeflateCompressionFormat = .zlib,
        bytes input: [UInt8],
        maximumSize: Int
    ) throws(DeflateError) -> [UInt8] {
        let decompressor = DeflateDecompressor()
        return try decompressor.decompress(format: format, bytes: input, maximumSize: maximumSize)
    }
}