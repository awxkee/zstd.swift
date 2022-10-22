//
//  zstd.swift
//
//
//  Created by Radzivon Bartoshyk on 22/10/2022.
//

import Foundation
import zstdc

public struct ZStd {

    public static func compress(data: Data, to: URL, compressionLevel: Int? = nil, threads: Int = 4) throws {
        let inputStream = InputStream(data: data)
        guard let outputStream = OutputStream(url: to, append: false) else {
            throw ZStdCannotOpenURLError(url: to)
        }
        do {
            return try compress(src: inputStream, dst: outputStream,
                                compressionLevel: compressionLevel, threads: threads)
        } catch {
            inputStream.close()
            outputStream.close()
            throw error
        }
    }

    public static func compress(from: URL, to: URL, compressionLevel: Int? = nil, threads: Int = 4) throws {
        guard let inputStream = InputStream(url: from) else {
            throw ZStdCannotOpenURLError(url: from)
        }
        guard let outputStream = OutputStream(url: to, append: false) else {
            throw ZStdCannotOpenURLError(url: to)
        }
        do {
            return try compress(src: inputStream, dst: outputStream,
                                compressionLevel: compressionLevel, threads: threads)
        } catch {
            inputStream.close()
            outputStream.close()
            throw error
        }
    }

    public static func decompress(src: URL) throws -> Data {
        guard let inputStream = InputStream(url: src) else {
            throw ZStdCannotOpenURLError(url: src)
        }
        let outputStream = OutputStream(toMemory: ())
        do {
            try decompress(src: inputStream, dst: outputStream)
            guard let content = outputStream.property(forKey: Stream.PropertyKey.dataWrittenToMemoryStreamKey) as? NSData else {
                throw ZStdWritingFromStreamSignalledError()
            }
            return content as Data
        } catch {
            inputStream.close()
            outputStream.close()
            throw error
        }
    }


    /**
     - Streams will be opened automatically
     - Streams will be closed only on successfull compression
     */
    public static func decompress(src: InputStream, dst: OutputStream) throws {

        let cctx = ZSTD_createDCtx()

        let inBufSize = ZSTD_DStreamInSize()
        let outBufSize = ZSTD_DStreamOutSize()
        guard let srcBuf = malloc(inBufSize) else {
            throw ZStdOutOfMemoryError(requiredSize: inBufSize)
        }
        guard let dstBuf = malloc(outBufSize) else {
            throw ZStdOutOfMemoryError(requiredSize: inBufSize)
        }
        let toRead = inBufSize
        src.open()
        dst.open()
        var readSize: Int = 1
        var isEmpty = true
        while readSize != 0 {
            isEmpty = false
            readSize = src.read(srcBuf, maxLength: toRead)
            if readSize == -1 {
                ZSTD_freeDCtx(cctx)
                src.close()
                dst.close()
                throw ZStdReadingFromStreamSignalledError()
            }
            
            var input = ZSTD_inBuffer(src: srcBuf, size: readSize, pos: 0)

            while input.pos < input.size {
                var output = ZSTD_outBuffer(dst: dstBuf, size: outBufSize, pos: 0)
                let remaining = ZSTD_decompressStream(cctx, &output, &input)
                if ZSTD_isError(remaining) != 0 {
                    ZSTD_freeDCtx(cctx)
                    src.close()
                    dst.close()
                    throw ZStdUnderlyingError(code: remaining,
                                              error: String(utf8String: ZSTD_getErrorName(remaining)) ?? "")
                }
                dst.write(dstBuf, maxLength: output.pos)
            }
        }
        ZSTD_freeDCtx(cctx)
        src.close()
        dst.close()

        if isEmpty {
            throw ZStdReadingFromStreamSignalledError()
        }
    }

    /**
     - Streams will be opened automatically
     - Streams will be closed only on successfull compression
     */
    public static func compress(src: InputStream, dst: OutputStream,
                                compressionLevel: Int? = nil, threads: Int = 4) throws {
        var level = ZSTD_defaultCLevel()
        if let compressionLevel {
            guard ZSTD_minCLevel()...ZSTD_maxCLevel() ~= Int32(compressionLevel) else {
                throw ZStdInvalidCompressionLevelError(level: compressionLevel)
            }
            level = Int32(compressionLevel)
        }

        let cctx = ZSTD_createCCtx()
        var ret = ZSTD_CCtx_setParameter(cctx, ZSTD_c_compressionLevel, level)
        try checkErrorCode(code: ret)
        ret = ZSTD_CCtx_setParameter(cctx, ZSTD_c_checksumFlag, 1)
        try checkErrorCode(code: ret)
        ret = ZSTD_CCtx_setParameter(cctx, ZSTD_c_nbWorkers, Int32(threads))
        try checkErrorCode(code: ret)

        let inBufSize = ZSTD_CStreamInSize()
        let outBufSize = ZSTD_CStreamOutSize()
        guard let srcBuf = malloc(inBufSize) else {
            throw ZStdOutOfMemoryError(requiredSize: inBufSize)
        }
        guard let dstBuf = malloc(outBufSize) else {
            throw ZStdOutOfMemoryError(requiredSize: inBufSize)
        }
        let toRead = inBufSize
        var compressed = false
        src.open()
        dst.open()
        while !compressed {
            let readSize = src.read(srcBuf, maxLength: toRead)
            if readSize == -1 {
                ZSTD_freeCCtx(cctx)
                src.close()
                dst.close()
                throw ZStdReadingFromStreamSignalledError()
            }
            let lastChunk = readSize < toRead
            let directive = lastChunk ? ZSTD_e_end : ZSTD_e_continue

            var input = ZSTD_inBuffer(src: srcBuf, size: readSize, pos: 0)

            var finished = false
            while !finished {
                var output = ZSTD_outBuffer(dst: dstBuf, size: outBufSize, pos: 0)
                let remaining = ZSTD_compressStream2(cctx, &output, &input, directive)
                if ZSTD_isError(remaining) != 0 {
                    ZSTD_freeCCtx(cctx)
                    src.close()
                    dst.close()
                    throw ZStdUnderlyingError(code: remaining,
                                              error: String(utf8String: ZSTD_getErrorName(remaining)) ?? "")
                }
                dst.write(dstBuf, maxLength: output.pos)
                finished = lastChunk ? (remaining == 0) : (input.pos == input.size)
            }

            if lastChunk {
                compressed = true
                break
            }
        }

        ZSTD_freeCCtx(cctx)
        src.close()
        dst.close()
    }

    public static func compress(_ data: Data, compressionLevel: Int? = nil) throws -> Data {
        var level = ZSTD_defaultCLevel()
        if let compressionLevel {
            guard ZSTD_minCLevel()...ZSTD_maxCLevel() ~= Int32(compressionLevel) else {
                throw ZStdInvalidCompressionLevelError(level: compressionLevel)
            }
            level = Int32(compressionLevel)
        }

        let boundSize = ZSTD_compressBound(data.count)
        try checkErrorCode(code: boundSize)
        guard let finalBuffer = malloc(boundSize) else {
            throw ZStdOutOfMemoryError(requiredSize: boundSize)
        }
        let compressedSize = data.withUnsafeBytes { (rawPointer: UnsafeRawBufferPointer) in
            ZSTD_compress(finalBuffer, boundSize, rawPointer.baseAddress, data.count, level)
        }
        if ZSTD_isError(compressedSize) != 0 {
            free(finalBuffer)
            throw ZStdUnderlyingError(code: compressedSize,
                                      error: String(utf8String: ZSTD_getErrorName(compressedSize)) ?? "")
        }
        return Data(bytesNoCopy: finalBuffer, count: compressedSize, deallocator: .free)
    }

    public static func decompress(_ data: Data) throws -> Data {
        try data.withUnsafeBytes { (rawPointer: UnsafeRawBufferPointer) in
            let maxBound = ZSTD_getFrameContentSize(rawPointer.baseAddress, data.count)
            if maxBound == ZSTD_CONTENTSIZE_ERROR || maxBound == ZSTD_CONTENTSIZE_UNKNOWN {
                throw ZStdRecognitionError()
            }
            guard maxBound > 0 else {
                throw ZStdOutOfMemoryError(requiredSize: Int(maxBound))
            }
            guard let buffer = malloc(Int(maxBound)) else {
                throw ZStdOutOfMemoryError(requiredSize: Int(maxBound))
            }
            let decompressedSize = ZSTD_decompress(buffer, Int(maxBound), rawPointer.baseAddress, data.count)
            if ZSTD_isError(decompressedSize) != 0 {
                free(buffer)
                throw ZStdUnderlyingError(code: decompressedSize,
                                          error: String(utf8String: ZSTD_getErrorName(decompressedSize)) ?? "")
            }
            
            return Data(bytesNoCopy: buffer, count: decompressedSize, deallocator: .free)
        }
    }

    private static func checkErrorCode(code: Int) throws {
        if ZSTD_isError(code) != 0 {
            throw ZStdUnderlyingError(code: code,
                                      error: String(utf8String: ZSTD_getErrorName(code)) ?? "")
        }
    }
}
