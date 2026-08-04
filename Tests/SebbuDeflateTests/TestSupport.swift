// Copyright (c) 2026 Sebastian Toivonen
// SPDX-License-Identifier: MIT

import Testing
@testable import SebbuDeflate

enum ExpectedDeflateError {
    case badData
    case shortOutput
    case insufficientSpace
}

func expectDeflateError(
    _ expected: ExpectedDeflateError,
    performing operation: () throws -> Void
) {
    do {
        try operation()
        Issue.record("Expected DeflateError.\(expected), but the operation succeeded")
    } catch let error as DeflateError {
        let matches = switch (expected, error) {
            case (.badData, .badData): true
            case (.shortOutput, .shortOutput): true
            case (.insufficientSpace, .insufficientSpace): true
            default: false
        }

        if !matches {
            Issue.record("Expected DeflateError.\(expected), but received \(error)")
        }
    } catch {
        Issue.record("Expected DeflateError.\(expected), but received \(error)")
    }
}

func compressionBound(
    format: DeflateCompressionFormat,
    level: DeflateCompressionLevel,
    inputCount: Int
) -> Int {
    let compressor = DeflateCompressor(level: level)
    return compressor.compressedByteCountBound(
        format: format,
        byteCount: inputCount
    )
}

func withTypedOutputBuffer(
    capacity: Int,
    initializedBytes: [UInt8] = [],
    _ body: (inout OutputSpan<UInt8>) throws -> Void
) throws -> [UInt8] {
    precondition(initializedBytes.count <= capacity)

    return try .init(capacity: capacity) {
        (output: inout OutputSpan<UInt8>) throws in

        for byte in initializedBytes {
            output.append(byte)
        }
        try body(&output)
    }
}

func compressUsingTypedSpan(
    _ input: [UInt8],
    format: DeflateCompressionFormat,
    level: DeflateCompressionLevel,
    useStaticAPI: Bool = false
) throws -> [UInt8] {
    let bound = compressionBound(
        format: format,
        level: level,
        inputCount: input.count
    )

    if useStaticAPI {
        return try .init(capacity: bound) {
            (output: inout OutputSpan<UInt8>) throws in

            try DeflateCompressor.compress(
                format: format,
                level: level,
                bytes: input.span,
                into: &output
            )
        }
    }

    let compressor = DeflateCompressor(level: level)
    return try .init(capacity: bound) {
        (output: inout OutputSpan<UInt8>) throws in

        try compressor.compress(
            format: format,
            bytes: input.span,
            into: &output
        )
    }
}

func decompressUsingTypedOutputSpan(
    _ input: [UInt8],
    format: DeflateCompressionFormat,
    capacity: Int,
    useStaticAPI: Bool = false
) throws -> [UInt8] {
    if useStaticAPI {
        return try .init(capacity: capacity) {
            (output: inout OutputSpan<UInt8>) throws in

            try DeflateDecompressor.decompress(
                format: format,
                bytes: input.span,
                into: &output
            )
        }
    }

    let decompressor = DeflateDecompressor()
    return try .init(capacity: capacity) {
        (output: inout OutputSpan<UInt8>) throws in

        try decompressor.decompress(
            format: format,
            bytes: input.span,
            into: &output
        )
    }
}

func decompressUsingTypedMutableSpan(
    _ input: [UInt8],
    format: DeflateCompressionFormat,
    exactSize: Int,
    useStaticAPI: Bool = false
) throws -> [UInt8] {
    var output = [UInt8](repeating: 0xa5, count: exactSize)

    do {
        var outputSpan = output.mutableSpan
        if useStaticAPI {
            try DeflateDecompressor.decompress(
                format: format,
                bytes: input.span,
                into: &outputSpan
            )
        } else {
            let decompressor = DeflateDecompressor()
            try decompressor.decompress(
                format: format,
                bytes: input.span,
                into: &outputSpan
            )
        }
    }

    return output
}

func withRawOutputBuffer(
    byteCount: Int,
    initializedBytes: [UInt8] = [],
    _ body: (inout OutputRawSpan) throws -> Void
) throws -> [UInt8] {
    precondition(initializedBytes.count <= byteCount)

    return try withUnsafeTemporaryAllocation(
        byteCount: byteCount,
        alignment: MemoryLayout<UInt8>.alignment
    ) { buffer throws -> [UInt8] in
        for index in initializedBytes.indices {
            buffer[index] = initializedBytes[index]
        }

        var output = OutputRawSpan(
            buffer: buffer,
            initializedCount: initializedBytes.count
        )
        defer {
            _ = output.finalize(for: buffer)
            output = OutputRawSpan()
        }

        try body(&output)
        return output.bytes.withUnsafeBytes { Array($0) }
    }
}

func compressUsingRawSpan(
    _ input: [UInt8],
    format: DeflateCompressionFormat,
    level: DeflateCompressionLevel,
    useStaticAPI: Bool = false
) throws -> [UInt8] {
    let bound = compressionBound(
        format: format,
        level: level,
        inputCount: input.count
    )

    return try withRawOutputBuffer(byteCount: bound) { output in
        if useStaticAPI {
            try DeflateCompressor.compress(
                format: format,
                level: level,
                bytes: input.span.bytes,
                into: &output
            )
        } else {
            let compressor = DeflateCompressor(level: level)
            try compressor.compress(
                format: format,
                bytes: input.span.bytes,
                into: &output
            )
        }
    }
}

func decompressUsingRawOutputSpan(
    _ input: [UInt8],
    format: DeflateCompressionFormat,
    capacity: Int,
    useStaticAPI: Bool = false
) throws -> [UInt8] {
    try withRawOutputBuffer(byteCount: capacity) { output in
        if useStaticAPI {
            try DeflateDecompressor.decompress(
                format: format,
                bytes: input.span.bytes,
                into: &output
            )
        } else {
            let decompressor = DeflateDecompressor()
            try decompressor.decompress(
                format: format,
                bytes: input.span.bytes,
                into: &output
            )
        }
    }
}

func decompressUsingRawMutableSpan(
    _ input: [UInt8],
    format: DeflateCompressionFormat,
    exactSize: Int,
    useStaticAPI: Bool = false
) throws -> [UInt8] {
    var output = [UInt8](repeating: 0xa5, count: exactSize)

    try output.withUnsafeMutableBytes { buffer throws in
        var outputSpan = buffer.mutableBytes
        if useStaticAPI {
            try DeflateDecompressor.decompress(
                format: format,
                bytes: input.span.bytes,
                into: &outputSpan
            )
        } else {
            let decompressor = DeflateDecompressor()
            try decompressor.decompress(
                format: format,
                bytes: input.span.bytes,
                into: &outputSpan
            )
        }
    }

    return output
}

func requireSendable<T: Sendable>(_: T.Type) {}