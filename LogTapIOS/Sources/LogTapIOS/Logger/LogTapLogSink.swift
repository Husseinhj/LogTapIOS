//
//  LogTapLogSink.swift
//  LogTapIOS
//
//  Created by Hussein Habibi Juybari on 06.09.25.
//

import Foundation

/// Minimal sink protocol your LogTap logger/server implements.
/// Implement this in your project to push into your LogTap store / WS stream.
public protocol LogTapLogSink {
    func emitLog(level: LogLevel, tag: String?, message: String)
}
