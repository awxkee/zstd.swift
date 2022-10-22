# zstd-swift

Simple implementation of prebuilt facebook/zstd in swift

```swift
// Simple compress usage
let compressedData = try ZStd.compress(Data())

// Simple decompress usage
let decompressedData = try ZStd.decompress(zstdCompressedData)

// Compress decomression made by Streams API

try ZStd.compress(src: InputStream(), dst: OutputStream())
try ZStd.decompress(src: InputStream(), dst: OutputStream())

// or you may use prebuilt functions on top of the streams
let data: Data = try ZStd.decompress(src: InputStream()))
// etc..


```
