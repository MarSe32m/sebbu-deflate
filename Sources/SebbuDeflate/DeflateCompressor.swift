import CLibDeflate

/// A reusable compressor for raw DEFLATE, zlib and gzip data.
///
/// Each call produces an independent compressed stream. The compressor does not
/// retain streaming state between calls.
///
/// Reusing a compressor avoids repeatedly allocating the underlying libdeflate
/// compressor. A single instance must not be used by overlapping compression
/// operations. Create a separate compressor for each concurrently executing task
/// or thread.
///
/// `DeflateCompressor` performs whole-buffer compression and does not provide a
/// streaming compression API.
public struct DeflateCompressor: ~Copyable {
    @usableFromInline
    internal let compressor: OpaquePointer

    /// Creates a reusable compressor with the specified compression level.
    ///
    /// The compression level is used for every compression operation performed
    /// by this instance.
    ///
    /// - Parameter level: The compression level to use. The default is
    ///   ``DeflateCompressionLevel/balanced``.
    @inlinable
    public init(level: DeflateCompressionLevel = .balanced) {
        // The default libdeflate_alloc_compressor() returns NULL only when running out of memory
        // or if the compression level is invalid. However, DeflateCompressionLevel takes care of
        // always having valid values.
        guard let compressor = libdeflate_alloc_compressor(level.rawValue) else {
            preconditionFailure("Couldn't allocate new compressor due to running out of memory")
        }
        self.compressor = compressor
    }

    /// Returns an upper bound on the size of the compressed representation.
    ///
    /// Use this method to determine how much output capacity is sufficient for
    /// compressing an input of the given size. The actual compressed result may
    /// be smaller than the returned value.
    ///
    /// - Parameters:
    ///   - format: The container format of the compressed data.
    ///   - byteCount: The number of uncompressed input bytes.
    /// - Returns: The maximum number of bytes required for the compressed result.
    /// - Precondition: `byteCount` is nonnegative.
    @inlinable
    public func compressedByteCountBound(
        format: DeflateCompressionFormat,
        byteCount: Int
    ) -> Int {
        precondition(byteCount >= 0, "Byte count must be non-negative")
        return switch format {
            case .raw:
                libdeflate_deflate_compress_bound(compressor, byteCount)
            case .zlib:
                libdeflate_zlib_compress_bound(compressor, byteCount)
            case .gzip:
                libdeflate_gzip_compress_bound(compressor, byteCount)
        }
    }

    /// Compresses a raw span of bytes into an output span.
    ///
    /// The compressed data is written into the available capacity of `output`.
    /// On success, the initialized region of `output` is extended by the number
    /// of compressed bytes produced.
    ///
    /// This method requires `output` to have at least the capacity returned by
    /// ``compressedByteCountBound(format:byteCount:)``. The actual compressed
    /// result may occupy less space.
    ///
    /// - Parameters:
    ///   - format: The container format to produce. The default is zlib.
    ///   - input: The bytes to compress.
    ///   - output: The output span into which the compressed data is written.
    /// - Throws: ``DeflateError/insufficientSpace`` if `output` does not have
    ///   sufficient free capacity.
    @inlinable
    public func compress(
        format: DeflateCompressionFormat = .zlib,
        bytes input: RawSpan, 
        into output: inout OutputRawSpan
    ) throws(DeflateError) {
        let bound = compressedByteCountBound(format: format, byteCount: input.byteCount)
        if output.freeCapacity < bound {
            throw .insufficientSpace
        }
        let bytesCompressed = input.withUnsafeBytes { input in 
            output.withUnsafeMutableBytes { output, initializedCount in 
                let output = 
                    UnsafeMutableRawBufferPointer(
                        start: output.baseAddress?.advanced(by: initializedCount), 
                        count: output.count - initializedCount
                    )
                let bytesCompressed = _compress(format: format, bytes: input, into: output)
                initializedCount += bytesCompressed
                return bytesCompressed
            }
        }
        if bytesCompressed == 0 {
            // Not enough room in the output span
            throw .insufficientSpace
        }
    }

    /// Compresses a span of bytes into an output span.
    ///
    /// The compressed data is written into the available capacity of `output`.
    /// On success, the initialized region of `output` is extended by the number
    /// of compressed bytes produced.
    ///
    /// This method requires `output` to have at least the capacity returned by
    /// ``compressedByteCountBound(format:byteCount:)``. The actual compressed
    /// result may occupy less space.
    ///
    /// - Parameters:
    ///   - format: The container format to produce. The default is zlib.
    ///   - input: The bytes to compress.
    ///   - output: The output span into which the compressed data is written.
    /// - Throws: ``DeflateError/insufficientSpace`` if `output` does not have
    ///   sufficient free capacity.
    @inlinable
    public func compress(
        format: DeflateCompressionFormat = .zlib,
        bytes input: Span<UInt8>,
        into output: inout OutputSpan<UInt8>
    ) throws(DeflateError) {
        let bound = compressedByteCountBound(format: format, byteCount: input.count)
        if output.freeCapacity < bound {
            throw .insufficientSpace
        }
        let bytesCompressed = input.withUnsafeBufferPointer { input in 
            output.withUnsafeMutableBufferPointer { output, initializedCount in 
                let output = 
                    UnsafeMutableBufferPointer<UInt8>(
                        start: output.baseAddress?.advanced(by: initializedCount), 
                        count: output.count - initializedCount
                    )
                let bytesCompressed = _compress(format: format, bytes: input, into: output)
                initializedCount += bytesCompressed
                return bytesCompressed
            }
        }
        if bytesCompressed == 0 {
            // Not enough room in the output span
            throw .insufficientSpace
        }
    }

    /// Compresses an array of bytes.
    ///
    /// This method allocates an appropriately sized output array and returns only
    /// the initialized bytes containing the compressed representation.
    ///
    /// - Parameters:
    ///   - format: The container format to produce. The default is zlib.
    ///   - input: The bytes to compress.
    /// - Returns: The compressed representation of `input`.
    /// - Throws: A ``DeflateError`` if compression fails.
    @inlinable
    public func compress(
        format: DeflateCompressionFormat = .zlib,
        bytes input: [UInt8]
    ) throws(DeflateError) -> [UInt8] {
        let bound = compressedByteCountBound(format: format, byteCount: input.count)
        return try .init(capacity: bound) { (output: inout OutputSpan<UInt8>) throws(DeflateError) -> Void in 
            try compress(format: format, bytes: input.span, into: &output)
        }
    }

    @inlinable
    internal func _compress(
        format: DeflateCompressionFormat,
        bytes input: UnsafeRawBufferPointer,
        into output: UnsafeMutableRawBufferPointer
    ) -> Int {
        switch format {
            case .raw:
            libdeflate_deflate_compress(compressor, input.baseAddress, input.count, output.baseAddress, output.count)
            case .zlib:
            libdeflate_zlib_compress(compressor, input.baseAddress, input.count, output.baseAddress, output.count)
            case .gzip:
            libdeflate_gzip_compress(compressor, input.baseAddress, input.count, output.baseAddress, output.count)
        }
    }

    @inlinable
    internal func _compress(
        format: DeflateCompressionFormat,
        bytes input: UnsafeBufferPointer<UInt8>,
        into output: UnsafeMutableBufferPointer<UInt8>
    ) -> Int {
        switch format {
            case .raw:
            libdeflate_deflate_compress(compressor, input.baseAddress, input.count, output.baseAddress, output.count)
            case .zlib:
            libdeflate_zlib_compress(compressor, input.baseAddress, input.count, output.baseAddress, output.count)
            case .gzip:
            libdeflate_gzip_compress(compressor, input.baseAddress, input.count, output.baseAddress, output.count)
        }
    }

    deinit {
        libdeflate_free_compressor(compressor)
    }
}

public extension DeflateCompressor {
    /// Compresses a raw span of bytes using a temporary compressor.
    ///
    /// For repeated compression operations, create and reuse a
    /// ``DeflateCompressor`` instance instead.
    ///
    /// - Parameters:
    ///   - format: The container format to produce. The default is zlib.
    ///   - level: The compression level to use. The default is balanced.
    ///   - input: The bytes to compress.
    ///   - output: The output span into which the compressed data is written.
    /// - Throws: ``DeflateError/insufficientSpace`` if `output` does not have
    ///   sufficient free capacity.
    @inlinable
    static func compress(
        format: DeflateCompressionFormat = .zlib,
        level: DeflateCompressionLevel = .balanced,
        bytes input: RawSpan, 
        into output: inout OutputRawSpan
    ) throws(DeflateError) {
        let compressor = DeflateCompressor(level: level)
        try compressor.compress(format: format, bytes: input, into: &output)
    }

    /// Compresses a span of bytes using a temporary compressor.
    ///
    /// For repeated compression operations, create and reuse a
    /// ``DeflateCompressor`` instance instead.
    ///
    /// - Parameters:
    ///   - format: The container format to produce. The default is zlib.
    ///   - level: The compression level to use. The default is balanced.
    ///   - input: The bytes to compress.
    ///   - output: The output span into which the compressed data is written.
    /// - Throws: ``DeflateError/insufficientSpace`` if `output` does not have
    ///   sufficient free capacity.
    @inlinable
    static func compress(
        format: DeflateCompressionFormat = .zlib,
        level: DeflateCompressionLevel = .balanced,
        bytes input: Span<UInt8>,
        into output: inout OutputSpan<UInt8>
    ) throws(DeflateError) {
        let compressor = DeflateCompressor(level: level)
        try compressor.compress(format: format, bytes: input, into: &output)
    }

    /// Compresses an array of bytes using a temporary compressor.
    ///
    /// This method allocates the output array automatically. For repeated
    /// compression operations, create and reuse a ``DeflateCompressor`` instance
    /// instead.
    ///
    /// - Parameters:
    ///   - format: The container format to produce. The default is zlib.
    ///   - level: The compression level to use. The default is balanced.
    ///   - input: The bytes to compress.
    /// - Returns: The compressed representation of `input`.
    /// - Throws: A ``DeflateError`` if compression fails.
    @inlinable
    static func compress(
        format: DeflateCompressionFormat = .zlib,
        level: DeflateCompressionLevel = .balanced,
        bytes input: [UInt8]
    ) throws(DeflateError) -> [UInt8] {
        let compressor = DeflateCompressor(level: level)
        return try compressor.compress(format: format, bytes: input)
    }
}