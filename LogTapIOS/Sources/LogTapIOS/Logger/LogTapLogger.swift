//
//  LogTapLogger.swift
//  LogTapIOS
//
//  Created by Hussein Habibi Juybari on 06.09.25.
//

import Foundation

public enum BuildMode {
  case debug, release
}

public final class LogTapLogger {
    public static let shared = LogTapLogger()
    private init() {}
    
    public var debugMode: Bool = true
    public var allowReleaseLogging: Bool = false
    public var minLevel: LogLevel = .debug
    
    private func shouldLog(_ level: LogLevel) -> Bool {
        guard allowReleaseLogging || debugMode else { return false }
        func rank(_ l: LogLevel) -> Int {
            switch l {
            case .verbose: return 0
            case .debug:   return 1
            case .info:    return 2
            case .warn:    return 3
            case .error:   return 4
            case .assert:  return 5
            }
        }
        return rank(level) >= rank(minLevel)
    }
    
    public func log(_ level: LogLevel,
                    _ message: @autoclosure () -> String,
                    tag: String? = nil,
                    file: StaticString = #fileID,
                    function: StaticString = #function,
                    line: UInt = #line)
    {
        guard shouldLog(level) else { return }
        let autoTag = tag ?? String(describing: file).split(separator: "/").last.map(String.init) ?? "LogTap"
        let msg = message()
        let ev = LogEvent(
            kind: .log,
            direction: .state,
            summary: msg,
            bodyPreview: msg,
            level: level,
            tag: autoTag
        )
        LogTap.shared.emit(ev)
        // Also forward to OSLog/print for convenience:
        print("[\(level.rawValue)] \(autoTag): \(msg)")
    }
    
    internal func v(_ msg: @autoclosure () -> String, tag: String? = nil) { log(.verbose, msg(), tag: tag) }
    internal func d(_ msg: @autoclosure () -> String, tag: String? = nil) { log(.debug,   msg(), tag: tag) }
    internal func i(_ msg: @autoclosure () -> String, tag: String? = nil) { log(.info,    msg(), tag: tag) }
    internal func w(_ msg: @autoclosure () -> String, tag: String? = nil) { log(.warn,    msg(), tag: tag) }
    internal func e(_ msg: @autoclosure () -> String, tag: String? = nil) { log(.error,   msg(), tag: tag) }
    internal func a(_ msg: @autoclosure () -> String, tag: String? = nil) { log(.assert,  msg(), tag: tag) }
}

public func logV(_ msg: @autoclosure () -> String, file: String = #file, line: UInt = #line) {
    let tag = URL(fileURLWithPath: file).lastPathComponent
    
    LogTapLogger.shared.v(msg(), tag: tag + " (L:\(line))")
}
public func logD(_ msg: @autoclosure () -> String, file: String = #file, line: UInt = #line) {
    let tag = URL(fileURLWithPath: file).lastPathComponent

    LogTapLogger.shared.d(msg(), tag: tag + " (L:\(line))")
}
public func logI(_ msg: @autoclosure () -> String, file: String = #file, line: UInt = #line) {
    let tag = URL(fileURLWithPath: file).lastPathComponent

    LogTapLogger.shared.i(msg(), tag: tag + " (L:\(line))")
}
public func logW(_ msg: @autoclosure () -> String, file: String = #file, line: UInt = #line) {
    let tag = URL(fileURLWithPath: file).lastPathComponent

    LogTapLogger.shared.w(msg(), tag: tag + " (L:\(line))")
}
public func logE(_ msg: @autoclosure () -> String, file: String = #file, line: UInt = #line) {
    let tag = URL(fileURLWithPath: file).lastPathComponent

    LogTapLogger.shared.e(msg(), tag: tag + " (L:\(line))")
}
public func logA(_ msg: @autoclosure () -> String, file: String = #file, line: UInt = #line) {
    let tag = URL(fileURLWithPath: file).lastPathComponent

    LogTapLogger.shared.a(msg(), tag: tag + " (L:\(line))")
}
