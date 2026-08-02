/// An error produced by a compression or decompression operation.
public enum DeflateError: Sendable, Error {
    /// The compressed input is invalid, corrupt, or unsupported.
    ///
    /// This error can occur when the input does not conform to the selected
    /// ``DeflateCompressionFormat`` or contains a malformed compressed stream.
    case badData

    /// The decompressed data is smaller than the expected output size.
    ///
    /// This error occurs during exact-size decompression when the compressed
    /// stream ends before the provided output span has been completely filled.
    ///
    /// This does not mean that the output buffer is too small; that condition
    /// is represented by ``insufficientSpace``.
    case shortOutput

    /// The destination does not have sufficient capacity for the result.
    ///
    /// During compression, this means the destination lacks the required free
    /// capacity for the compressed representation. During decompression, it
    /// means the uncompressed data is larger than the provided output storage.
    case insufficientSpace
}