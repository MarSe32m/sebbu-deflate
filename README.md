# SebbuDeflate

SebbuDeflate is a Swift package wrapping [libdeflate](https://github.com/ebiggers/libdeflate), a highly optimized library for DEFLATE-based compression and decompression.

The package builds libdeflate directly from source and provides modern, type-safe Swift APIs for working with raw DEFLATE, zlib and gzip data.

## Features

* Modern Swift interface to libdeflate
* Raw DEFLATE, zlib and gzip support
* Reusable compressor and decompressor types
* Foundation-free core library
* Optional convenience APIs for `Foundation.Data`
* libdeflate’s optimized implementations and runtime CPU-feature detection

## Library products

SebbuDeflate provides two library products.

### `SebbuDeflate`

The main library provides the core compression and decompression APIs.

It does not depend on Foundation and is designed around Swift standard-library and buffer types. Applications and libraries that do not otherwise use Foundation can therefore use SebbuDeflate without introducing it as a dependency.

```swift
import SebbuDeflate
```

### `SebbuDeflateFoundation`

`SebbuDeflateFoundation` is an optional library that builds on `SebbuDeflate` and provides convenience APIs for `Foundation.Data`.

```swift
import SebbuDeflateFoundation
```

Importing `SebbuDeflateFoundation` also makes the core SebbuDeflate APIs available. Foundation is only required by this optional target; the main `SebbuDeflate` library remains Foundation-free.

## Installation

Add SebbuDeflate as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(
        url: "https://github.com/MarSe32m/sebbu-deflate.git",
        from: "1.25.0"
    )
]
```

For the Foundation-free APIs, add the `SebbuDeflate` product to your target:

```swift
.target(
    name: "MyTarget",
    dependencies: [
        .product(
            name: "SebbuDeflate",
            package: "sebbu-deflate"
        )
    ]
)
```

To use the `Data` convenience APIs, depend on `SebbuDeflateFoundation` instead:

```swift
.target(
    name: "MyTarget",
    dependencies: [
        .product(
            name: "SebbuDeflateFoundation",
            package: "sebbu-deflate"
        )
    ]
)
```

## Usage

For one-off compression and decompression operations, use the static convenience methods:

```swift
import SebbuDeflate

let input = Array("Hello from SebbuDeflate!".utf8)

let compressed = try DeflateCompressor.compress(
    format: .gzip,
    level: .balanced,
    bytes: input
)

let decompressed = try DeflateDecompressor.decompress(
    format: .gzip,
    bytes: compressed,
    exactSize: input.count
)

assert(decompressed == input)
```

Use `exactSize` when the uncompressed byte count is known. If only an upper bound is available, use `maximumSize` instead. The returned array contains only the bytes actually decompressed:

```swift
let decompressed = try DeflateDecompressor.decompress(
    format: .gzip,
    bytes: compressed,
    maximumSize: 1_024
)
```

For repeated operations, create and reuse compressor and decompressor instances:

```swift
let compressor = DeflateCompressor(level: .best)
let decompressor = DeflateDecompressor()

let compressed = try compressor.compress(
    format: .zlib,
    bytes: input
)

let decompressed = try decompressor.decompress(
    format: .zlib,
    bytes: compressed,
    exactSize: input.count
)
```

A single instance must not be used by overlapping operations. Create a separate compressor or decompressor for each concurrently executing task.

### Using Foundation `Data`

The `SebbuDeflateFoundation` target provides equivalent convenience APIs for `Data`:

```swift
import Foundation
import SebbuDeflateFoundation

let input = Data("Hello from SebbuDeflate!".utf8)

let compressed = try DeflateCompressor.compress(
    format: .zlib,
    level: .balanced,
    bytes: input
)

let decompressed = try DeflateDecompressor.decompress(
    format: .zlib,
    bytes: compressed,
    exactSize: input.count
)

assert(decompressed == input)
```

SebbuDeflate supports raw DEFLATE (`.raw`), zlib (`.zlib`), and gzip (`.gzip`). The compression and decompression formats must match. The default format is zlib.



## About libdeflate

libdeflate is designed for fast whole-buffer compression and decompression. It is particularly well suited to independently compressed blocks and files whose uncompressed size is known.

Unlike zlib, libdeflate does not provide a streaming compression API. SebbuDeflate follows the same whole-buffer model.

## License

The bundled libdeflate source code is distributed under the MIT License. See the included license and attribution files for details.
