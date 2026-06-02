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
     - Streams will be closed on completion or error
     */
    public static func decompress(src: InputStream, dst: OutputStream) throws {
        guard let cctx = ZSTD_createDCtx() else {
            throw ZStdOutOfMemoryError(requiredSize: 0)
        }
        defer { ZSTD_freeDCtx(cctx) }

        let inBufSize  = ZSTD_DStreamInSize()
        let outBufSize = ZSTD_DStreamOutSize()

        guard let srcBuf = malloc(inBufSize) else {
            throw ZStdOutOfMemoryError(requiredSize: inBufSize)
        }
        defer { free(srcBuf) }

        guard let dstBuf = malloc(outBufSize) else {
            throw ZStdOutOfMemoryError(requiredSize: outBufSize)
        }
        defer { free(dstBuf) }

        src.open()
        dst.open()
        defer {
            src.close()
            dst.close()
        }

        var isEmpty = true

        while true {
            let readSize = src.read(srcBuf, maxLength: inBufSize)

            if readSize == 0 { break }   // EOF clean exit

            if readSize < 0 {
                throw ZStdReadingFromStreamSignalledError()
            }

            isEmpty = false

            var input = ZSTD_inBuffer(src: srcBuf, size: readSize, pos: 0)
            while input.pos < input.size {
                var output = ZSTD_outBuffer(dst: dstBuf, size: outBufSize, pos: 0)
                let remaining = ZSTD_decompressStream(cctx, &output, &input)

                if ZSTD_isError(remaining) != 0 {
                    throw ZStdUnderlyingError(
                        code: remaining,
                        error: String(utf8String: ZSTD_getErrorName(remaining)) ?? "")
                }

                if output.pos > 0 {
                    dst.write(dstBuf, maxLength: output.pos)
                }

                if remaining == 0 {
                    ZSTD_DCtx_reset(cctx, ZSTD_reset_session_only)
                }
            }
        }

        if isEmpty {
            throw ZStdReadingFromStreamSignalledError()
        }
    }

    /**
     - Streams will be opened automatically
     - Streams will be closed on completion or error
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

        guard let cctx = ZSTD_createCCtx() else {
            throw ZStdOutOfMemoryError(requiredSize: 0)
        }
        defer { ZSTD_freeCCtx(cctx) }

        var ret = ZSTD_CCtx_setParameter(cctx, ZSTD_c_compressionLevel, level)
        try checkErrorCode(code: ret)
        ret = ZSTD_CCtx_setParameter(cctx, ZSTD_c_checksumFlag, 1)
        try checkErrorCode(code: ret)
        ret = ZSTD_CCtx_setParameter(cctx, ZSTD_c_nbWorkers, Int32(threads))
        try checkErrorCode(code: ret)

        let inBufSize  = ZSTD_CStreamInSize()
        let outBufSize = ZSTD_CStreamOutSize()

        guard let srcBuf = malloc(inBufSize) else {
            throw ZStdOutOfMemoryError(requiredSize: inBufSize)
        }
        defer { free(srcBuf) }

        guard let dstBuf = malloc(outBufSize) else {
            throw ZStdOutOfMemoryError(requiredSize: outBufSize)
        }
        defer { free(dstBuf) }

        src.open()
        dst.open()
        defer {
            src.close()
            dst.close()
        }

        var compressed = false
        while !compressed {
            let readSize = src.read(srcBuf, maxLength: inBufSize)

            if readSize < 0 {
                throw ZStdReadingFromStreamSignalledError()
            }

            let lastChunk = readSize < inBufSize
            let directive: ZSTD_EndDirective = lastChunk ? ZSTD_e_end : ZSTD_e_continue

            var input = ZSTD_inBuffer(src: srcBuf, size: readSize, pos: 0)

            var finished = false
            repeat {
                var output = ZSTD_outBuffer(dst: dstBuf, size: outBufSize, pos: 0)
                let remaining = ZSTD_compressStream2(cctx, &output, &input, directive)

                if ZSTD_isError(remaining) != 0 {
                    throw ZStdUnderlyingError(
                        code: remaining,
                        error: String(utf8String: ZSTD_getErrorName(remaining)) ?? "")
                }

                if output.pos > 0 {
                    dst.write(dstBuf, maxLength: output.pos)
                }

                finished = lastChunk ? (remaining == 0) : (input.pos == input.size)
            } while !finished

            if lastChunk { compressed = true }
        }
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
        let src = InputStream(data: data)
        let dst = OutputStream(toMemory: ())
        try decompress(src: src, dst: dst)
        guard let content = dst.property(forKey: .dataWrittenToMemoryStreamKey) as? NSData else {
            throw ZStdWritingFromStreamSignalledError()
        }
        return content as Data
    }

    private static func checkErrorCode(code: Int) throws {
        if ZSTD_isError(code) != 0 {
            throw ZStdUnderlyingError(code: code,
                                      error: String(utf8String: ZSTD_getErrorName(code)) ?? "")
        }
    }
}
