#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Testing
@testable import SebbuDeflateFoundation

private struct NamedDataPayload: Sendable {
    let name: String
    let data: Data
}

private enum FoundationTestPayloads {
    static let representative = [
        NamedDataPayload(name: "empty", data: Data()),
        NamedDataPayload(name: "one byte", data: Data([0x41])),
        NamedDataPayload(
            name: "UTF-8 text",
            data: Data(
                "SebbuDeflateFoundation: Καλημέρα, maailma, hello!".utf8
            )
        ),
        NamedDataPayload(
            name: "every byte value",
            data: Data((0...255).map(UInt8.init))
        ),
        NamedDataPayload(
            name: "large repetitive data",
            data: Data(repeating: 0x41, count: 65_536)
        ),
        NamedDataPayload(
            name: "large pseudo-random data",
            data: pseudoRandomData(
                count: 65_537,
                seed: 0x1234_5678_9abc_def0
            )
        ),
    ]

    static func pseudoRandomData(count: Int, seed: UInt64) -> Data {
        var state = seed
        return Data((0..<count).map { _ in
            state = state &* 6_364_136_223_846_793_005
                &+ 1_442_695_040_888_963_407
            return UInt8(truncatingIfNeeded: state >> 32)
        })
    }
}

private struct FoundationExternalFixture: Sendable {
    let format: DeflateCompressionFormat
    let compressed: Data
    let uncompressed: Data
}

private let foundationExternalPayload = Data("hello, libdeflate!".utf8)

private let foundationExternalFixtures = [
    FoundationExternalFixture(
        format: .raw,
        compressed: Data([
            0xcb, 0x48, 0xcd, 0xc9, 0xc9, 0xd7, 0x51, 0xc8, 0xc9, 0x4c,
            0x4a, 0x49, 0x4d, 0xcb, 0x49, 0x2c, 0x49, 0x55, 0x04, 0x00,
        ]),
        uncompressed: foundationExternalPayload
    ),
    FoundationExternalFixture(
        format: .zlib,
        compressed: Data([
            0x78, 0x9c, 0xcb, 0x48, 0xcd, 0xc9, 0xc9, 0xd7, 0x51, 0xc8,
            0xc9, 0x4c, 0x4a, 0x49, 0x4d, 0xcb, 0x49, 0x2c, 0x49, 0x55,
            0x04, 0x00, 0x3f, 0x57, 0x06, 0x8e,
        ]),
        uncompressed: foundationExternalPayload
    ),
    FoundationExternalFixture(
        format: .gzip,
        compressed: Data([
            0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03,
            0xcb, 0x48, 0xcd, 0xc9, 0xc9, 0xd7, 0x51, 0xc8, 0xc9, 0x4c,
            0x4a, 0x49, 0x4d, 0xcb, 0x49, 0x2c, 0x49, 0x55, 0x04, 0x00,
            0xcb, 0x54, 0xb6, 0xec, 0x12, 0x00, 0x00, 0x00,
        ]),
        uncompressed: foundationExternalPayload
    ),
]

@Suite("SebbuDeflateFoundation")
struct DeflateFoundationTests {
    @Test("Default one-shot Data APIs round-trip")
    func defaultOneShotAPIs() throws {
        let input = Data("The default format is zlib.".utf8)

        let compressed = try DeflateCompressor.compress(bytes: input)
        let restored = try DeflateDecompressor.decompress(
            bytes: compressed,
            exactSize: input.count
        )
        let bounded = try DeflateDecompressor.decompress(
            bytes: compressed,
            maximumSize: input.count + 128
        )

        #expect(restored == input)
        #expect(bounded == input)
        #expect(bounded.count == input.count)
    }

    @Test("Reusable Data APIs round-trip representative inputs in every format")
    func reusableDataAPIs() throws {
        let compressor = DeflateCompressor(level: .balanced)
        let decompressor = DeflateDecompressor()

        for payload in FoundationTestPayloads.representative {
            for format in DeflateCompressionFormat.allCases {
                let compressed = try compressor.compress(
                    format: format,
                    bytes: payload.data
                )
                let restored = try decompressor.decompress(
                    format: format,
                    bytes: compressed,
                    exactSize: payload.data.count
                )

                #expect(
                    restored == payload.data,
                    "Failed for \(payload.name) using \(format)"
                )
            }
        }
    }

    @Test("Static Data APIs support every compression level and format")
    func everyLevelAndFormat() throws {
        let input = FoundationTestPayloads.pseudoRandomData(
            count: 16_384,
            seed: 0xcafe_babe_f00d_1234
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

    @Test("Data compression respects the reported bound")
    func compressionBound() throws {
        for payload in FoundationTestPayloads.representative {
            let compressor = DeflateCompressor(level: .best)

            for format in DeflateCompressionFormat.allCases {
                let bound = compressor.compressedByteCountBound(
                    format: format,
                    byteCount: payload.data.count
                )
                let compressed = try compressor.compress(
                    format: format,
                    bytes: payload.data
                )

                #expect(compressed.count <= bound)
            }
        }
    }

    @Test("Data exact-size decompression distinguishes size mismatches")
    func exactSize() throws {
        let input = Data("The expected size is part of the contract.".utf8)

        for format in DeflateCompressionFormat.allCases {
            let compressed = try DeflateCompressor.compress(
                format: format,
                bytes: input
            )

            let exact = try DeflateDecompressor.decompress(
                format: format,
                bytes: compressed,
                exactSize: input.count
            )
            #expect(exact == input)

            expectDeflateError(.shortOutput) {
                _ = try DeflateDecompressor.decompress(
                    format: format,
                    bytes: compressed,
                    exactSize: input.count + 1
                )
            }

            let decompressor = DeflateDecompressor()
            expectDeflateError(.insufficientSpace) {
                _ = try decompressor.decompress(
                    format: format,
                    bytes: compressed,
                    exactSize: input.count - 1
                )
            }
        }
    }

    @Test("Data maximum-size APIs return the actual decompressed length")
    func maximumSize() throws {
        let input = Data(
            "A maximum size may safely overestimate the output.".utf8
        )
        let decompressor = DeflateDecompressor()

        for format in DeflateCompressionFormat.allCases {
            let compressed = try DeflateCompressor.compress(
                format: format,
                bytes: input
            )

            let exactCapacity = try decompressor.decompress(
                format: format,
                bytes: compressed,
                maximumSize: input.count
            )
            let overestimatedCapacity = try DeflateDecompressor.decompress(
                format: format,
                bytes: compressed,
                maximumSize: input.count + 1_024
            )

            #expect(exactCapacity == input)
            #expect(overestimatedCapacity == input)
            #expect(overestimatedCapacity.count == input.count)

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
        }
    }

    @Test("Data convenience APIs handle empty output with zero capacity")
    func emptyDataConvenienceAPIs() throws {
        for format in DeflateCompressionFormat.allCases {
            let compressed = try DeflateCompressor.compress(
                format: format,
                bytes: Data()
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

    @Test("Foundation and core overloads interoperate")
    func coreInteroperability() throws {
        let input = FoundationTestPayloads.pseudoRandomData(
            count: 32_769,
            seed: 0x0ddc_0ffe_e15e_beef
        )

        for format in DeflateCompressionFormat.allCases {
            let dataCompressed = try DeflateCompressor.compress(
                format: format,
                bytes: input
            )
            let arrayRestored = try DeflateDecompressor.decompress(
                format: format,
                bytes: Array(dataCompressed),
                exactSize: input.count
            )
            #expect(arrayRestored == Array(input))

            let arrayCompressed = try DeflateCompressor.compress(
                format: format,
                bytes: Array(input)
            )
            let dataRestored = try DeflateDecompressor.decompress(
                format: format,
                bytes: Data(arrayCompressed),
                exactSize: input.count
            )
            #expect(dataRestored == input)
        }
    }

    @Test("Data overloads decompress external fixtures")
    func externalFixtures() throws {
        let decompressor = DeflateDecompressor()

        for fixture in foundationExternalFixtures {
            let restored = try decompressor.decompress(
                format: fixture.format,
                bytes: fixture.compressed,
                exactSize: fixture.uncompressed.count
            )
            #expect(restored == fixture.uncompressed)
        }
    }

    @Test("Invalid and truncated Data inputs map to badData")
    func invalidAndTruncatedData() throws {
        for format in DeflateCompressionFormat.allCases {
            expectDeflateError(.badData) {
                _ = try DeflateDecompressor.decompress(
                    format: format,
                    bytes: Data([0xff]),
                    exactSize: 64
                )
            }
            expectDeflateError(.badData) {
                _ = try DeflateDecompressor.decompress(
                    format: format,
                    bytes: Data([0xff]),
                    maximumSize: 64
                )
            }

            let input = Data("A stream that will be truncated.".utf8)
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
        let input = Data("Checksummed payload".utf8)

        for format: DeflateCompressionFormat in [.zlib, .gzip] {
            var compressed = try DeflateCompressor.compress(
                format: format,
                bytes: input
            )
            compressed[compressed.index(before: compressed.endIndex)] ^= 0xff

            expectDeflateError(.badData) {
                _ = try DeflateDecompressor.decompress(
                    format: format,
                    bytes: compressed,
                    exactSize: input.count
                )
            }
        }
    }

    @Test("One-shot Data APIs can run concurrently")
    func concurrentOneShotAPIs() async throws {
        try await withThrowingTaskGroup(of: Bool.self) { group in
            for index in 0..<24 {
                group.addTask {
                    let input = FoundationTestPayloads.pseudoRandomData(
                        count: 4_096 + index * 31,
                        seed: UInt64(index) + 1
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
                    let restored: Data
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