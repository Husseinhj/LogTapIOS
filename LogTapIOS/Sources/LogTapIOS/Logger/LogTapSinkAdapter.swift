//
//  LogTapSinkAdapter.swift
//  LogTapIOS
//
//  Created by Hussein Habibi Juybari on 06.09.25.
//

import Foundation

public final class LogTapSinkAdapter: LogTapLogSink {
    public init() {}
    public func emitLog(level: LogLevel, tag: String?, message: String) {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let lvlTxt = level.rawValue
        let tagPrefix = tag.map { "[\($0)] " } ?? ""
        let summary = "[\(lvlTxt)] \(tagPrefix)\(message)"
        
        // Build a minimal LogEvent that won’t trigger the logger again
        var ev = LogEvent(
            id: 0,
            ts: nowMs,
            kind: .log,
            direction: .outbound,
            summary: message,
            url: nil,
            method: nil,
            status: nil,
            reason: nil,
            headers: nil,
            bodyPreview: nil,
            bodyIsTruncated: false,
            bodyBytes: nil,
            tookMs: nil,
            thread: Thread.current.name ?? "main"
        )
        
        ev.level = level
        ev.tag = tag
        
        Task {
            LogTap.shared.store.add(ev)
        }
    }
}
