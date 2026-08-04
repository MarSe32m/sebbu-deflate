// Copyright (c) 2026 Sebastian Toivonen
// SPDX-License-Identifier: MIT

import Testing
@testable import SebbuDeflate

private struct NamedPayload: Sendable {
    let name: String
    let bytes: [UInt8]
}

private enum TestPayloads {
    static let empty = NamedPayload(name: "empty", bytes: [])
    static let oneByte = NamedPayload(name: "one byte", bytes: [0x41])
    static let text = NamedPayload(
        name: "UTF-8 text",
        bytes: Array(
            "Libdeflate from Swift: Καλημέρα, maailma, hello!".utf8
        )
    )
    static let everyByte = NamedPayload(
        name: "every byte value",
        bytes: (0...255).map(UInt8.init)
    )
    static let highlyCompressible = NamedPayload(
        name: "highly compressible",
        bytes: Array(repeating: 0x41, count: 65_536)
    )
    static let incompressible = NamedPayload(
        name: "deterministic pseudo-random",
        bytes: pseudoRandomBytes(count: 65_536, seed: 0xC0FF_EE12_3456_7890)
    )

    static let representative = [
        empty,
        oneByte,
        text,
        everyByte,
        highlyCompressible,
        incompressible,
    ]

    static func patternedBytes(count: Int) -> [UInt8] {
        (0..<count).map { index in
            UInt8(truncatingIfNeeded: (index &* 31) ^ (index >> 3))
        }
    }

    static func pseudoRandomBytes(count: Int, seed: UInt64) -> [UInt8] {
        var state = seed
        return (0..<count).map { _ in
            state = state &* 6_364_136_223_846_793_005
                &+ 1_442_695_040_888_963_407
            return UInt8(truncatingIfNeeded: state >> 32)
        }
    }
}

private struct ExternalFixture: Sendable {
    let format: DeflateCompressionFormat
    let compressed: [UInt8]
    let uncompressed: [UInt8]
}

private let externalPayload = Array("hello, libdeflate!".utf8)

// Produced independently with zlib/gzip. These exercise decoder
// interoperability without constraining libdeflate's encoder output.
private let externalFixtures = [
    ExternalFixture(
        format: .raw,
        compressed: [
            0xcb, 0x48, 0xcd, 0xc9, 0xc9, 0xd7, 0x51, 0xc8, 0xc9, 0x4c,
            0x4a, 0x49, 0x4d, 0xcb, 0x49, 0x2c, 0x49, 0x55, 0x04, 0x00,
        ],
        uncompressed: externalPayload
    ),
    ExternalFixture(
        format: .zlib,
        compressed: [
            0x78, 0x9c, 0xcb, 0x48, 0xcd, 0xc9, 0xc9, 0xd7, 0x51, 0xc8,
            0xc9, 0x4c, 0x4a, 0x49, 0x4d, 0xcb, 0x49, 0x2c, 0x49, 0x55,
            0x04, 0x00, 0x3f, 0x57, 0x06, 0x8e,
        ],
        uncompressed: externalPayload
    ),
    ExternalFixture(
        format: .gzip,
        compressed: [
            0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03,
            0xcb, 0x48, 0xcd, 0xc9, 0xc9, 0xd7, 0x51, 0xc8, 0xc9, 0x4c,
            0x4a, 0x49, 0x4d, 0xcb, 0x49, 0x2c, 0x49, 0x55, 0x04, 0x00,
            0xcb, 0x54, 0xb6, 0xec, 0x12, 0x00, 0x00, 0x00,
        ],
        uncompressed: externalPayload
    ),
]

@Suite("DeflateCompressionLevel")
struct DeflateCompressionLevelTests {
    @Test("Accepts every supported Int32 value")
    func acceptsSupportedInt32Values() {
        for value in Int32(0)...Int32(12) {
            #expect(DeflateCompressionLevel(rawValue: value)?.rawValue == value)
        }
    }

    @Test("Accepts every supported Int value")
    func acceptsSupportedIntValues() {
        for value in 0...12 {
            #expect(
                DeflateCompressionLevel(rawValue: value)?.rawValue
                    == Int32(value)
            )
        }
    }

    @Test("Rejects unsupported values")
    func rejectsUnsupportedValues() {
        for value: Int32 in [-100, -1, 13, 100] {
            #expect(DeflateCompressionLevel(rawValue: value)?.rawValue == nil)
        }

        for value in [Int.min, -100, -1, 13, 100, Int.max] {
            #expect(DeflateCompressionLevel(rawValue: value)?.rawValue == nil)
        }
    }

    @Test("Named levels have their documented values")
    func namedLevels() {
        #expect(DeflateCompressionLevel.noCompression.rawValue == 0)
        #expect(DeflateCompressionLevel.fastest.rawValue == 1)
        #expect(DeflateCompressionLevel.balanced.rawValue == 6)
        #expect(DeflateCompressionLevel.best.rawValue == 12)
    }

    @Test("Is Sendable")
    func isSendable() {
        requireSendable(DeflateCompressionLevel.self)
    }
}

@Suite("DeflateCompressionFormat")
struct DeflateCompressionFormatTests {
    @Test("Contains exactly raw, zlib and gzip")
    func allCases() {
        #expect(DeflateCompressionFormat.allCases.count == 3)

        var rawCount = 0
        var zlibCount = 0
        var gzipCount = 0
        for format in DeflateCompressionFormat.allCases {
            switch format {
                case .raw: rawCount += 1
                case .zlib: zlibCount += 1
                case .gzip: gzipCount += 1
            }
        }

        #expect(rawCount == 1)
        #expect(zlibCount == 1)
        #expect(gzipCount == 1)
    }

    @Test("Is Sendable")
    func isSendable() {
        requireSendable(DeflateCompressionFormat.self)
    }
}

@Suite("DeflateError")
struct DeflateErrorTests {
    @Test("Is an Error and is Sendable")
    func conformances() {
        func requireError<T: Error>(_: T.Type) {}
        requireError(DeflateError.self)
        requireSendable(DeflateError.self)
    }
}

@Suite("Deflate compression")
struct DeflateCompressionTests {
    @Test("Default array APIs round-trip with exact and maximum sizes")
    func defaultArrayAPIs() throws {
        let input = Array("The default format is zlib.".utf8)

        let compressor = DeflateCompressor()
        let decompressor = DeflateDecompressor()
        let instanceCompressed = try compressor.compress(bytes: input)
        let maximumRestored = try decompressor.decompress(
            bytes: instanceCompressed,
            maximumSize: input.count + 128
        )
        #expect(maximumRestored == input)
        #expect(maximumRestored.count == input.count)

        let staticCompressed = try DeflateCompressor.compress(bytes: input)
        let exactRestored = try DeflateDecompressor.decompress(
            bytes: staticCompressed,
            exactSize: input.count
        )
        #expect(exactRestored == input)
    }

    @Test("Array convenience APIs support exact and maximum sizes")
    func arrayConvenienceAPIs() throws {
        let input = TestPayloads.text.bytes
        let decompressor = DeflateDecompressor()

        for format in DeflateCompressionFormat.allCases {
            let compressed = try DeflateCompressor.compress(
                format: format,
                bytes: input
            )

            let exactInstance = try decompressor.decompress(
                format: format,
                bytes: compressed,
                exactSize: input.count
            )
            let exactStatic = try DeflateDecompressor.decompress(
                format: format,
                bytes: compressed,
                exactSize: input.count
            )
            let maximumInstance = try decompressor.decompress(
                format: format,
                bytes: compressed,
                maximumSize: input.count + 257
            )
            let maximumStatic = try DeflateDecompressor.decompress(
                format: format,
                bytes: compressed,
                maximumSize: input.count
            )

            #expect(exactInstance == input)
            #expect(exactStatic == input)
            #expect(maximumInstance == input)
            #expect(maximumStatic == input)
            #expect(maximumInstance.count == input.count)
        }
    }

    @Test("Array convenience APIs handle empty output with zero capacity")
    func emptyArrayConvenienceAPIs() throws {
        for format in DeflateCompressionFormat.allCases {
            let compressed = try DeflateCompressor.compress(
                format: format,
                bytes: []
            )

            let decompressor = DeflateDecompressor()
            let exact = try decompressor.decompress(
                format: format,
                bytes: compressed,
                exactSize: 0
            )
            let maximum = try DeflateDecompressor.decompress(
                format: format,
                bytes: compressed,
                maximumSize: 0
            )

            #expect(exact.isEmpty)
            #expect(maximum.isEmpty)
        }
    }

    @Test("Round-trips representative payloads in every format")
    func representativeRoundTrips() throws {
        let levels: [DeflateCompressionLevel] = [
            .noCompression,
            .fastest,
            .balanced,
            .best,
        ]

        for payload in TestPayloads.representative {
            for format in DeflateCompressionFormat.allCases {
                for level in levels {
                    let compressed = try DeflateCompressor.compress(
                        format: format,
                        level: level,
                        bytes: payload.bytes
                    )
                    let restored = try DeflateDecompressor.decompress(
                        format: format,
                        bytes: compressed,
                        exactSize: payload.bytes.count
                    )

                    #expect(
                        restored == payload.bytes,
                        "Failed for \(payload.name), \(format), level \(level.rawValue)"
                    )
                }
            }
        }
    }

    @Test("Round-trips every compression level")
    func everyCompressionLevel() throws {
        let input = TestPayloads.pseudoRandomBytes(
            count: 16_384,
            seed: 0x1234_5678_9abc_def0
        )

        for rawLevel in 0...12 {
            let level = DeflateCompressionLevel(rawValue: rawLevel)!
            for format in DeflateCompressionFormat.allCases {
                let compressed = try DeflateCompressor.compress(
                    format: format,
                    level: level,
                    bytes: input
                )
                let restored = try DeflateDecompressor.decompress(
                    format: format,
                    bytes: compressed,
                    exactSize: input.count
                )
                #expect(restored == input)
            }
        }
    }

    @Test("Round-trips sizes around DEFLATE boundaries")
    func boundarySizes() throws {
        let sizes = [
            0, 1, 2, 3,
            31, 32, 33,
            255, 256, 257,
            32_767, 32_768, 32_769,
            65_535, 65_536, 65_537,
        ]

        for size in sizes {
            let input = TestPayloads.patternedBytes(count: size)
            for format in DeflateCompressionFormat.allCases {
                let compressed = try DeflateCompressor.compress(
                    format: format,
                    bytes: input
                )
                let restored = try DeflateDecompressor.decompress(
                    format: format,
                    bytes: compressed,
                    exactSize: size
                )
                #expect(restored == input, "Failed at size \(size) for \(format)")
            }
        }
    }

    @Test("Compressed output never exceeds its reported bound")
    func compressionBounds() throws {
        let inputs = TestPayloads.representative.map(\.bytes)

        for rawLevel in 0...12 {
            let level = DeflateCompressionLevel(rawValue: rawLevel)!
            let compressor = DeflateCompressor(level: level)

            for format in DeflateCompressionFormat.allCases {
                for input in inputs {
                    let firstBound = compressor.compressedByteCountBound(
                        format: format,
                        byteCount: input.count
                    )
                    let secondBound = compressor.compressedByteCountBound(
                        format: format,
                        byteCount: input.count
                    )
                    let compressed = try compressor.compress(
                        format: format,
                        bytes: input
                    )

                    #expect(firstBound == secondBound)
                    #expect(firstBound >= input.count)
                    #expect(compressed.count <= firstBound)
                }
            }
        }
    }

    @Test("A compressor and decompressor can be reused across operations and formats")
    func reusableInstances() throws {
        let compressor = DeflateCompressor(level: .balanced)
        let decompressor = DeflateDecompressor()

        for iteration in 0..<100 {
            let input = TestPayloads.pseudoRandomBytes(
                count: (iteration &* 997) % 20_000,
                seed: UInt64(iteration) &+ 1
            )

            for format in DeflateCompressionFormat.allCases {
                let compressed = try compressor.compress(
                    format: format,
                    bytes: input
                )
                let restored = try decompressor.decompress(
                    format: format,
                    bytes: compressed,
                    exactSize: input.count
                )
                #expect(restored == input)
            }
        }
    }

    @Test("Deterministic property corpus round-trips")
    func deterministicPropertyCorpus() throws {
        for index in 0..<48 {
            let size = (index &* 7_919) % 70_000
            let input = TestPayloads.pseudoRandomBytes(
                count: size,
                seed: UInt64(index) &* 0x9e37_79b9_7f4a_7c15 &+ 1
            )
            let level = DeflateCompressionLevel(rawValue: index % 13)!

            for format in DeflateCompressionFormat.allCases {
                let compressed = try DeflateCompressor.compress(
                    format: format,
                    level: level,
                    bytes: input
                )
                let restored = try DeflateDecompressor.decompress(
                    format: format,
                    bytes: compressed,
                    exactSize: input.count
                )
                #expect(restored == input)
            }
        }
    }

    @Test("One-shot APIs are safe to use concurrently")
    func concurrentOneShotOperations() async throws {
        try await withThrowingTaskGroup(of: Bool.self) { group in
            for index in 0..<32 {
                group.addTask {
                    let input = TestPayloads.pseudoRandomBytes(
                        count: 4_096 + index &* 37,
                        seed: UInt64(index) &+ 10
                    )
                    let level = DeflateCompressionLevel(rawValue: index % 13)!
                    let format: DeflateCompressionFormat = switch index % 3 {
                        case 0: .raw
                        case 1: .zlib
                        default: .gzip
                    }

                    let compressed = try DeflateCompressor.compress(
                        format: format,
                        level: level,
                        bytes: input
                    )
                    let restored: [UInt8]
                    if index.isMultiple(of: 2) {
                        restored = try DeflateDecompressor.decompress(
                            format: format,
                            bytes: compressed,
                            exactSize: input.count
                        )
                    } else {
                        restored = try DeflateDecompressor.decompress(
                            format: format,
                            bytes: compressed,
                            maximumSize: input.count + 64
                        )
                    }
                    return restored == input
                }
            }

            for try await succeeded in group {
                #expect(succeeded)
            }
        }
    }
}

@Suite("Span overloads")
struct DeflateSpanTests {
    @Test("Typed instance overloads round-trip and report actual output count")
    func typedInstanceOverloads() throws {
        let input = TestPayloads.text.bytes

        for format in DeflateCompressionFormat.allCases {
            let compressed = try compressUsingTypedSpan(
                input,
                format: format,
                level: .balanced
            )

            let boundedOutput = try decompressUsingTypedOutputSpan(
                compressed,
                format: format,
                capacity: input.count + 128
            )
            #expect(boundedOutput == input)
            #expect(boundedOutput.count == input.count)

            let exactOutput = try decompressUsingTypedMutableSpan(
                compressed,
                format: format,
                exactSize: input.count
            )
            #expect(exactOutput == input)
        }
    }

    @Test("Typed static overloads round-trip")
    func typedStaticOverloads() throws {
        let input = TestPayloads.everyByte.bytes

        for format in DeflateCompressionFormat.allCases {
            let compressed = try compressUsingTypedSpan(
                input,
                format: format,
                level: .fastest,
                useStaticAPI: true
            )
            let boundedOutput = try decompressUsingTypedOutputSpan(
                compressed,
                format: format,
                capacity: input.count + 64,
                useStaticAPI: true
            )
            let exactOutput = try decompressUsingTypedMutableSpan(
                compressed,
                format: format,
                exactSize: input.count,
                useStaticAPI: true
            )

            #expect(boundedOutput == input)
            #expect(exactOutput == input)
        }
    }

    @Test("Raw instance overloads round-trip and report actual output count")
    func rawInstanceOverloads() throws {
        let input = TestPayloads.text.bytes

        for format in DeflateCompressionFormat.allCases {
            let compressed = try compressUsingRawSpan(
                input,
                format: format,
                level: .balanced
            )
            let boundedOutput = try decompressUsingRawOutputSpan(
                compressed,
                format: format,
                capacity: input.count + 128
            )
            let exactOutput = try decompressUsingRawMutableSpan(
                compressed,
                format: format,
                exactSize: input.count
            )

            #expect(boundedOutput == input)
            #expect(boundedOutput.count == input.count)
            #expect(exactOutput == input)
        }
    }

    @Test("Raw static overloads round-trip")
    func rawStaticOverloads() throws {
        let input = TestPayloads.everyByte.bytes

        for format in DeflateCompressionFormat.allCases {
            let compressed = try compressUsingRawSpan(
                input,
                format: format,
                level: .best,
                useStaticAPI: true
            )
            let boundedOutput = try decompressUsingRawOutputSpan(
                compressed,
                format: format,
                capacity: input.count + 64,
                useStaticAPI: true
            )
            let exactOutput = try decompressUsingRawMutableSpan(
                compressed,
                format: format,
                exactSize: input.count,
                useStaticAPI: true
            )

            #expect(boundedOutput == input)
            #expect(exactOutput == input)
        }
    }

    @Test("Output spans append after their initialized region")
    func outputSpansAppendAfterInitializedRegion() throws {
        let prefix: [UInt8] = [0xde, 0xad, 0xbe, 0xef]
        let input = TestPayloads.text.bytes

        for format in DeflateCompressionFormat.allCases {
            let compressor = DeflateCompressor(level: .balanced)
            let bound = compressor.compressedByteCountBound(
                format: format,
                byteCount: input.count
            )

            let typedContainer = try withTypedOutputBuffer(
                capacity: prefix.count + bound,
                initializedBytes: prefix
            ) { output in
                try compressor.compress(
                    format: format,
                    bytes: input.span,
                    into: &output
                )
            }
            #expect(Array(typedContainer.prefix(prefix.count)) == prefix)

            let typedCompressed = Array(typedContainer.dropFirst(prefix.count))
            let typedRestored = try withTypedOutputBuffer(
                capacity: prefix.count + input.count + 64,
                initializedBytes: prefix
            ) { output in
                let decompressor = DeflateDecompressor()
                try decompressor.decompress(
                    format: format,
                    bytes: typedCompressed.span,
                    into: &output
                )
            }
            #expect(typedRestored == prefix + input)

            let rawContainer = try withRawOutputBuffer(
                byteCount: prefix.count + bound,
                initializedBytes: prefix
            ) { output in
                try DeflateCompressor.compress(
                    format: format,
                    bytes: input.span.bytes,
                    into: &output
                )
            }
            #expect(Array(rawContainer.prefix(prefix.count)) == prefix)

            let rawCompressed = Array(rawContainer.dropFirst(prefix.count))
            let rawRestored = try withRawOutputBuffer(
                byteCount: prefix.count + input.count + 64,
                initializedBytes: prefix
            ) { output in
                try DeflateDecompressor.decompress(
                    format: format,
                    bytes: rawCompressed.span.bytes,
                    into: &output
                )
            }
            #expect(rawRestored == prefix + input)
        }
    }

    @Test("Zero-capacity output handles an empty uncompressed result")
    func emptyBoundedOutput() throws {
        for format in DeflateCompressionFormat.allCases {
            let compressed = try DeflateCompressor.compress(
                format: format,
                bytes: []
            )
            let typed = try decompressUsingTypedOutputSpan(
                compressed,
                format: format,
                capacity: 0
            )
            let raw = try decompressUsingRawOutputSpan(
                compressed,
                format: format,
                capacity: 0
            )
            #expect(typed.isEmpty)
            #expect(raw.isEmpty)
        }
    }
}


@Suite("Deflate error handling")
struct DeflateErrorHandlingTests {
    @Test("Compression rejects typed and raw destinations smaller than the bound")
    func compressionInsufficientSpace() {
        let input = TestPayloads.incompressible.bytes
        let prefix: [UInt8] = [0xa5]

        for format in DeflateCompressionFormat.allCases {
            let compressor = DeflateCompressor(level: .balanced)
            let bound = compressor.compressedByteCountBound(
                format: format,
                byteCount: input.count
            )

            expectDeflateError(.insufficientSpace) {
                _ = try withTypedOutputBuffer(
                    capacity: prefix.count + bound - 1,
                    initializedBytes: prefix
                ) { output in
                    try compressor.compress(
                        format: format,
                        bytes: input.span,
                        into: &output
                    )
                }
            }

            expectDeflateError(.insufficientSpace) {
                _ = try withRawOutputBuffer(
                    byteCount: prefix.count + bound - 1,
                    initializedBytes: prefix
                ) { output in
                    try DeflateCompressor.compress(
                        format: format,
                        level: .balanced,
                        bytes: input.span.bytes,
                        into: &output
                    )
                }
            }
        }
    }

    @Test("Bounded decompression rejects insufficient capacity")
    func boundedDecompressionInsufficientSpace() throws {
        let input = TestPayloads.incompressible.bytes
        let prefix: [UInt8] = [0xa5]

        for format in DeflateCompressionFormat.allCases {
            let compressed = try DeflateCompressor.compress(
                format: format,
                bytes: input
            )

            expectDeflateError(.insufficientSpace) {
                _ = try withTypedOutputBuffer(
                    capacity: prefix.count + input.count - 1,
                    initializedBytes: prefix
                ) { output in
                    let decompressor = DeflateDecompressor()
                    try decompressor.decompress(
                        format: format,
                        bytes: compressed.span,
                        into: &output
                    )
                }
            }

            expectDeflateError(.insufficientSpace) {
                _ = try withRawOutputBuffer(
                    byteCount: prefix.count + input.count - 1,
                    initializedBytes: prefix
                ) { output in
                    try DeflateDecompressor.decompress(
                        format: format,
                        bytes: compressed.span.bytes,
                        into: &output
                    )
                }
            }
        }
    }

    @Test("Exact-size spans distinguish short output from insufficient space")
    func exactSizeErrors() throws {
        let input = TestPayloads.text.bytes

        for format in DeflateCompressionFormat.allCases {
            let compressed = try DeflateCompressor.compress(
                format: format,
                bytes: input
            )

            expectDeflateError(.shortOutput) {
                _ = try decompressUsingTypedMutableSpan(
                    compressed,
                    format: format,
                    exactSize: input.count + 1
                )
            }
            expectDeflateError(.insufficientSpace) {
                _ = try decompressUsingTypedMutableSpan(
                    compressed,
                    format: format,
                    exactSize: input.count - 1,
                    useStaticAPI: true
                )
            }

            expectDeflateError(.shortOutput) {
                _ = try decompressUsingRawMutableSpan(
                    compressed,
                    format: format,
                    exactSize: input.count + 1,
                    useStaticAPI: true
                )
            }
            expectDeflateError(.insufficientSpace) {
                _ = try decompressUsingRawMutableSpan(
                    compressed,
                    format: format,
                    exactSize: input.count - 1
                )
            }
        }
    }

    @Test("Array decompression enforces its documented exact size")
    func arrayExactSizeErrors() throws {
        let input = TestPayloads.text.bytes

        for format in DeflateCompressionFormat.allCases {
            let compressed = try DeflateCompressor.compress(
                format: format,
                bytes: input
            )

            expectDeflateError(.shortOutput) {
                _ = try DeflateDecompressor.decompress(
                    format: format,
                    bytes: compressed,
                    exactSize: input.count + 1
                )
            }
            expectDeflateError(.insufficientSpace) {
                _ = try DeflateDecompressor.decompress(
                    format: format,
                    bytes: compressed,
                    exactSize: input.count - 1
                )
            }
        }
    }

    @Test("Array maximum-size APIs reject only undersized destinations")
    func arrayMaximumSizeErrors() throws {
        let input = TestPayloads.text.bytes
        let decompressor = DeflateDecompressor()

        for format in DeflateCompressionFormat.allCases {
            let compressed = try DeflateCompressor.compress(
                format: format,
                bytes: input
            )

            expectDeflateError(.insufficientSpace) {
                _ = try decompressor.decompress(
                    format: format,
                    bytes: compressed,
                    maximumSize: input.count - 1
                )
            }
            expectDeflateError(.insufficientSpace) {
                _ = try DeflateDecompressor.decompress(
                    format: format,
                    bytes: compressed,
                    maximumSize: input.count - 1
                )
            }

            let overestimated = try DeflateDecompressor.decompress(
                format: format,
                bytes: compressed,
                maximumSize: input.count + 1_024
            )
            #expect(overestimated == input)
            #expect(overestimated.count == input.count)
        }
    }

    @Test("Every span decompression overload maps invalid data to badData")
    func spanInvalidData() {
        let invalid: [UInt8] = [0xff]

        for format in DeflateCompressionFormat.allCases {
            expectDeflateError(.badData) {
                _ = try decompressUsingTypedOutputSpan(
                    invalid,
                    format: format,
                    capacity: 64
                )
            }
            expectDeflateError(.badData) {
                _ = try decompressUsingRawOutputSpan(
                    invalid,
                    format: format,
                    capacity: 64,
                    useStaticAPI: true
                )
            }
            expectDeflateError(.badData) {
                _ = try decompressUsingTypedMutableSpan(
                    invalid,
                    format: format,
                    exactSize: 64,
                    useStaticAPI: true
                )
            }
            expectDeflateError(.badData) {
                _ = try decompressUsingRawMutableSpan(
                    invalid,
                    format: format,
                    exactSize: 64
                )
            }
        }
    }

    @Test("Clearly invalid data maps to badData in every format")
    func invalidData() {
        let invalid: [UInt8] = [0xff]

        for format in DeflateCompressionFormat.allCases {
            expectDeflateError(.badData) {
                _ = try DeflateDecompressor.decompress(
                    format: format,
                    bytes: invalid,
                    exactSize: 64
                )
            }
            expectDeflateError(.badData) {
                _ = try DeflateDecompressor.decompress(
                    format: format,
                    bytes: invalid,
                    maximumSize: 64
                )
            }
        }
    }

    @Test("Truncated streams map to badData")
    func truncatedStreams() throws {
        let input = TestPayloads.text.bytes

        for format in DeflateCompressionFormat.allCases {
            var compressed = try DeflateCompressor.compress(
                format: format,
                bytes: input
            )
            compressed.removeLast()

            expectDeflateError(.badData) {
                _ = try DeflateDecompressor.decompress(
                    format: format,
                    bytes: compressed,
                    exactSize: input.count
                )
            }
        }
    }

    @Test("Corrupt zlib and gzip checksums map to badData")
    func corruptChecksums() throws {
        let input = TestPayloads.text.bytes

        for format: DeflateCompressionFormat in [.zlib, .gzip] {
            var compressed = try DeflateCompressor.compress(
                format: format,
                bytes: input
            )
            compressed[compressed.count - 1] ^= 0xff

            expectDeflateError(.badData) {
                _ = try DeflateDecompressor.decompress(
                    format: format,
                    bytes: compressed,
                    exactSize: input.count
                )
            }
        }
    }

    @Test("Using the wrong wrapper format maps to badData")
    func wrongFormat() {
        let zlib = externalFixtures[1]
        let gzip = externalFixtures[2]

        expectDeflateError(.badData) {
            _ = try DeflateDecompressor.decompress(
                format: .gzip,
                bytes: zlib.compressed,
                exactSize: zlib.uncompressed.count
            )
        }
        expectDeflateError(.badData) {
            _ = try DeflateDecompressor.decompress(
                format: .zlib,
                bytes: gzip.compressed,
                exactSize: gzip.uncompressed.count
            )
        }
    }
}


@Suite("Deflate interoperability")
struct DeflateInteroperabilityTests {
    @Test("Decompresses externally produced raw, zlib and gzip fixtures")
    func externalDecoderFixtures() throws {
        let decompressor = DeflateDecompressor()

        for fixture in externalFixtures {
            let output = try decompressor.decompress(
                format: fixture.format,
                bytes: fixture.compressed,
                exactSize: fixture.uncompressed.count
            )
            #expect(output == fixture.uncompressed)
        }
    }

    @Test("zlib and gzip encoders emit the expected wrapper signatures")
    func wrapperSignatures() throws {
        let input = TestPayloads.text.bytes
        let zlib = try DeflateCompressor.compress(format: .zlib, bytes: input)
        let gzip = try DeflateCompressor.compress(format: .gzip, bytes: input)

        #expect(zlib.count >= 6)
        #expect((zlib[0] & 0x0f) == 8)
        #expect((((Int(zlib[0]) << 8) | Int(zlib[1])) % 31) == 0)

        #expect(gzip.count >= 18)
        #expect(gzip[0] == 0x1f)
        #expect(gzip[1] == 0x8b)
        #expect(gzip[2] == 8)
    }

    @Test("Trailing bytes after the first stream are ignored")
    func trailingInput() throws {
        let input = TestPayloads.text.bytes

        for format in DeflateCompressionFormat.allCases {
            var compressed = try DeflateCompressor.compress(
                format: format,
                bytes: input
            )
            compressed += [0xde, 0xad, 0xbe, 0xef]

            let restored = try DeflateDecompressor.decompress(
                format: format,
                bytes: compressed,
                exactSize: input.count
            )
            #expect(restored == input)
        }
    }

    @Test("Only the first member of concatenated gzip data is decompressed")
    func concatenatedGzipMembers() throws {
        let first = Array("first member".utf8)
        let second = Array("second member".utf8)
        let firstCompressed = try DeflateCompressor.compress(
            format: .gzip,
            bytes: first
        )
        let secondCompressed = try DeflateCompressor.compress(
            format: .gzip,
            bytes: second
        )

        let restored = try DeflateDecompressor.decompress(
            format: .gzip,
            bytes: firstCompressed + secondCompressed,
            exactSize: first.count
        )
        #expect(restored == first)
    }
}