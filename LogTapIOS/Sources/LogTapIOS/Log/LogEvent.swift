//
//  LogEvent.swift
//  LogTapIOS
//
//  Created by Hussein Habibi Juybari on 06.09.25.
//

import Foundation

public enum LogKind: String, Codable {
  case http = "HTTP"
  case websocket = "WEBSOCKET"
  case log = "LOG"
}

public enum Direction: String, Codable {
  case request = "REQUEST"
  case response = "RESPONSE"
  case outbound = "OUTBOUND"
  case inbound = "INBOUND"
  case state = "STATE"
  case error = "ERROR"
}

public enum LogLevel: String, Codable {
  case verbose = "VERBOSE"
  case debug = "DEBUG"
  case info = "INFO"
  case warn = "WARN"
  case error = "ERROR"
  case assert = "ASSERT"
}

public struct LogEvent: Codable {
    public var id: Int64
    public var ts: Int64
    public var kind: LogKind
    public var direction: Direction
    public var summary: String
    
    public var url: String?
    public var method: String?
    public var status: Int?
    public var code: Int?
    public var reason: String?
    
    public var headers: [String: [String]]?
    public var bodyPreview: String?
    public var bodyIsTruncated: Bool
    public var bodyBytes: Int?
    public var tookMs: Int64?
    public var thread: String
    public var level: LogLevel?
    public var tag: String?
    
    public init(
        id: Int64 = 0,
        ts: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        kind: LogKind,
        direction: Direction,
        summary: String,
        url: String? = nil,
        method: String? = nil,
        status: Int? = nil,
        code: Int? = nil,
        reason: String? = nil,
        headers: [String: [String]]? = nil,
        bodyPreview: String? = nil,
        bodyIsTruncated: Bool = false,
        bodyBytes: Int? = nil,
        tookMs: Int64? = nil,
        thread: String = Thread.isMainThread ? "main" : (Thread.current.name ?? "bg"),
        level: LogLevel? = nil,
        tag: String? = nil
    ) {
        self.id = id
        self.ts = ts
        self.kind = kind
        self.direction = direction
        self.summary = summary
        self.url = url
        self.method = method
        self.status = status
        self.code = code
        self.reason = reason
        self.headers = headers
        self.bodyPreview = bodyPreview
        self.bodyIsTruncated = bodyIsTruncated
        self.bodyBytes = bodyBytes
        self.tookMs = tookMs
        self.thread = thread
        self.level = level
        self.tag = tag
    }
}
