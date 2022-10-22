//
//  File.swift
//  
//
//  Created by Radzivon Bartoshyk on 22/10/2022.
//

import Foundation
import zstdc

public struct ZStdOutOfMemoryError: LocalizedError {
    let requiredSize: Int

    public var errorDescription: String? {
        "Can't allocate memory in size: \(requiredSize)"
    }
}

public struct ZStdInvalidCompressionLevelError: LocalizedError {
    let level: Int

    public var errorDescription: String? {
        "Invalid compression level: \(level); min: \(ZSTD_minCLevel()) max: \(ZSTD_maxCLevel())"
    }
}

public struct ZStdRecognitionError: LocalizedError {
    public var errorDescription: String? {
        "Buffer is not compressed by zstd"
    }
}

public struct ZStdUnderlyingError: LocalizedError {
    let code: Int
    let error: String

    public var errorDescription: String? {
        "ZStd responds with error code: \(code): \(error)"
    }
}

public struct ZStdCannotOpenURLError: LocalizedError {
    let url: URL

    public var errorDescription: String? {
        if url.scheme != "file" {
            return "Only 'file' scheme is supported. Can't open URL: \(url.absoluteString)"
        } else {
            return "Can't open URL: \(url.absoluteString)"
        }
    }
}

public struct ZStdReadingFromStreamSignalledError: LocalizedError {
    public var errorDescription: String? {
        "While reading of stream error was occur"
    }
}

public struct ZStdWritingFromStreamSignalledError: LocalizedError {
    public var errorDescription: String? {
        "While writing of stream error was occur"
    }
}
