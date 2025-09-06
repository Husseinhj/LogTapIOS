//
//  LogTapPrintBridge.swift
//  LogTapIOS
//
//  Created by Hussein Habibi Juybari on 06.09.25.
//

import Foundation
import Darwin


/// Bridge that hijacks stdout/stderr and streams lines into a LogTap sink.
public final class LogTapPrintBridge {

    /// Direct emit API so callers can provide a precise tag (e.g. basename of #fileID).
    public func emitDirect(message: String, level: LogLevel = .debug, tag: String? = nil) {
        sink?.emitLog(level: level, tag: tag, message: message)
    }

    public static let shared = LogTapPrintBridge()

    private var outPipe: Pipe?
    private var errPipe: Pipe?

    private var outOrig: Int32 = -1
    private var errOrig: Int32 = -1

    private var outBuffer = Data()
    private var errBuffer = Data()

    /// Where to send captured lines.
    private var sink: LogTapLogSink?

    /// If true, will try to parse a log level prefix in a line like: "[INFO] message"
    public var parseLevelTokens = true

    /// If true, when no tag is parsed from the line, use the caller's class/function from the backtrace.
    public var useCallerAsDefaultTag: Bool = true

    /// Use to avoid duplicate “ready” logs, reentrant, etc.
    private var isRunning = false
    private let q = DispatchQueue(label: "dev.flex.logtap.print-bridge")

    public init() {}

    /// Start capturing. Provide your concrete sink (e.g. your LogTap server/logger).
    public func start(sink: LogTapLogSink, captureStdout: Bool = true, captureStderr: Bool = true) {
        guard !isRunning else { return }
        self.sink = sink

        // Disable buffering so lines flush immediately.
        setbuf(stdout, nil)
        setbuf(stderr, nil)

        if captureStdout {
            let p = Pipe()
            outPipe = p
            outOrig = dup(STDOUT_FILENO)
            dup2(p.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
            p.fileHandleForReading.readabilityHandler = { [weak self] h in
                self?.consume(handle: h, isStdErr: false)
            }
        }

        if captureStderr {
            let p = Pipe()
            errPipe = p
            errOrig = dup(STDERR_FILENO)
            dup2(p.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
            p.fileHandleForReading.readabilityHandler = { [weak self] h in
                self?.consume(handle: h, isStdErr: true)
            }
        }

        isRunning = true
    }

    /// Stop capturing and restore original stdout/stderr.
    public func stop() {
        guard isRunning else { return }
        isRunning = false

        if let p = outPipe {
            p.fileHandleForReading.readabilityHandler = nil
            fflush(stdout)
            if outOrig >= 0 { dup2(outOrig, STDOUT_FILENO); close(outOrig); outOrig = -1 }
            p.fileHandleForWriting.closeFile()
            p.fileHandleForReading.closeFile()
            outPipe = nil
        }
        if let p = errPipe {
            p.fileHandleForReading.readabilityHandler = nil
            fflush(stderr)
            if errOrig >= 0 { dup2(errOrig, STDERR_FILENO); close(errOrig); errOrig = -1 }
            p.fileHandleForWriting.closeFile()
            p.fileHandleForReading.closeFile()
            errPipe = nil
        }

        outBuffer.removeAll(keepingCapacity: false)
        errBuffer.removeAll(keepingCapacity: false)
    }

    @_silgen_name("swift_demangle")
    private func _swift_demangle(_ mangledName: UnsafePointer<CChar>?,
                                 _ mangledNameLength: UInt,
                                 _ outputBuffer: UnsafeMutablePointer<CChar>?,
                                 _ outputBufferSize: UnsafeMutablePointer<UInt>?,
                                 _ flags: UInt32) -> UnsafeMutablePointer<CChar>?

    private func demangle(_ mangled: String) -> String? {
        return mangled.withCString { cstr -> String? in
            guard let demangledPtr = _swift_demangle(cstr, UInt(strlen(cstr)), nil, nil, 0) else { return nil }
            defer { free(demangledPtr) }
            return String(cString: demangledPtr)
        }
    }

    // MARK: - Internals

    private func consume(handle: FileHandle, isStdErr: Bool) {
        let data = handle.availableData
        if data.isEmpty { return } // pipe closed
        q.async {
            if isStdErr { self.errBuffer.append(data) } else { self.outBuffer.append(data) }
            self.drain(isStdErr: isStdErr)
        }
    }

    private func drain(isStdErr: Bool) {
        var buffer = isStdErr ? errBuffer : outBuffer
        while let range = buffer.firstRange(of: Data([0x0A])) { // newline
            let lineData = buffer.subdata(in: 0..<range.lowerBound)
            buffer.removeSubrange(0...range.lowerBound) // drop line + newline
            let line = String(data: lineData, encoding: .utf8) ?? String(decoding: lineData, as: UTF8.self)
            forward(line: line, isStdErr: isStdErr)
        }
        if isStdErr { errBuffer = buffer } else { outBuffer = buffer }
    }

    private func forward(line: String, isStdErr: Bool) {
        guard let sink = sink else { return }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if (isLogTapLog(trimmed)) {
            return
        }

        var level: LogLevel = isStdErr ? .error : .debug
        var message = trimmed
        var tag: String? = nil

        if parseLevelTokens {
            // Recognize: "[INFO] foo", "[ERROR] foo", "[W] tag: msg"
            if let m = message.range(of: #"^\s*\[(VERBOSE|DEBUG|INFO|WARN|ERROR|ASSERT|V|D|I|W|E|A)\]\s*"#, options: .regularExpression) {
                let token = String(message[m]).trimmingCharacters(in: .whitespacesAndNewlines)
                message.removeSubrange(m)
                let t = token
                    .replacingOccurrences(of: "[", with: "")
                    .replacingOccurrences(of: "]", with: "")
                    .uppercased()
                switch t {
                    case "VERBOSE", "V": level = .verbose
                    case "DEBUG",   "D": level = .debug
                    case "INFO",    "I": level = .info
                    case "WARN",    "W": level = .warn
                    case "ERROR",   "E": level = .error
                    case "ASSERT",  "A": level = .assert
                    default: break
                }
            }
            // Recognize classic "D/Tag: message" form
            if let m = message.range(of: #"^\s*([VDIWEA])\s*/\s*([^:()]+)(?:\([^)]*\))?\s*:\s*"#, options: .regularExpression) {
                let prefix = String(message[m])
                message.removeSubrange(m)
                if let lvChar = prefix.first?.uppercased() {
                    switch lvChar {
                        case "V": level = .verbose
                        case "D": level = .debug
                        case "I": level = .info
                        case "W": level = .warn
                        case "E": level = .error
                        case "A": level = .assert
                        default: break
                    }
                }
                if let tagMatch = prefix.split(separator: "/").last?.split(separator: ":").first {
                    tag = String(tagMatch).trimmingCharacters(in: .whitespaces)
                }
            }
        }

        if (tag == nil || tag!.isEmpty), useCallerAsDefaultTag {
            tag = "print"
        }

        sink.emitLog(level: level, tag: tag, message: message)
    }
}

/// Use this instead of `print` when you want the tag to be the **calling file** (e.g. `ContentView.swift`).
/// It still writes to stdout so Xcode shows it.
public func logtapPrint(_ items: Any...,
                        separator: String = " ",
                        terminator: String = "\n",
                        level: LogLevel = .debug,
                        fileID: String = #fileID) {
    let msg = items.map { String(describing: $0) }.joined(separator: separator)
    // Echo to stdout for Xcode console
    fputs((msg + terminator), stdout)
    // Derive file name from #fileID (e.g. "MyModule/Views/ContentView.swift" -> "ContentView.swift")
    let tag = (fileID.split(separator: "/").last.map(String.init)) ?? fileID
    LogTapPrintBridge.shared.emitDirect(message: msg, level: level, tag: tag)
}

internal func isLogTapLog(_ line: String) -> Bool {
    // Regex: filename (no spaces) + (L:<digits>): + message
    let pattern = #"[^\s]+\s*\(L:\s*\d+\):\s*.+$"#
    
    // Compile regex
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
        return false
    }
    
    let range = NSRange(line.startIndex..<line.endIndex, in: line)
    return regex.firstMatch(in: line, options: [], range: range) != nil
}
