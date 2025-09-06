//
//  WebSocketLogger.swift
//  LogTapIOS
//
//  Created by Hussein Habibi Juybari on 06.09.25.
//

import Foundation

/// Wrapper around URLSessionWebSocketTask to log send/receive events.
public final class LogTapWebSocket {
    private let task: URLSessionWebSocketTask
    private var isOpen = false
    
    public init(task: URLSessionWebSocketTask) {
        self.task = task
    }
    
    public func resume() {
        isOpen = true
        let u = task.originalRequest?.url?.absoluteString ?? "(unknown)"
        LogTap.shared.emit(
            LogEvent(
                kind: .websocket,
                direction: .state,
                summary: "WS OPEN \(u)",
                url: u,
                status: nil, 
                tag: "WebSocket"
            )
        )
        receiveLoop()
        task.resume()
    }
    
    public func send(_ text: String) {
        LogTap.shared.emit(
            LogEvent(
                kind: .websocket,
                direction: .outbound,
                summary: "WS → text \(text.prefix(80))\(text.count > 80 ? "…" : "")",
                bodyPreview: text,
                bodyIsTruncated: text.count > 10_000, 
                tag: "WebSocket"
            )
        )
        task.send(.string(text)) { error in
            if let error {
                LogTap.shared.emit(
                    LogEvent(
                        kind: .websocket,
                        direction: .error,
                        summary: "WS SEND ERROR \(error.localizedDescription)",
                        reason: error.localizedDescription, 
                        tag: "WebSocket"
                    )
                )
            }
        }
    }
    
    public func send(_ data: Data) {
        LogTap.shared.emit(
            LogEvent(
                kind: .websocket,
                direction: .outbound,
                summary: "WS → binary \(data.count) bytes",
                bodyBytes: data.count,
                tag: "WebSocket"
            )
        )
        task.send(.data(data)) { error in
            if let error {
                LogTap.shared.emit(
                    LogEvent(
                        kind: .websocket,
                        direction: .error,
                        summary: "WS SEND ERROR \(error.localizedDescription)",
                        reason: error.localizedDescription, 
                        tag: "WebSocket"
                    )
                )
            }
        }
    }
    
    public func cancel(with closeCode: URLSessionWebSocketTask.CloseCode = .normalClosure, reason: Data? = nil) {
        task.cancel(with: closeCode, reason: reason)
        isOpen = false
        LogTap.shared.emit(
            LogEvent(
                kind: .websocket,
                direction: .state,
                summary: "WS CLOSE \(closeCode.rawValue)",
                tag: "WebSocket"
            )
        )
    }
    
    private func receiveLoop() {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                switch msg {
                case .string(let s):
                    LogTap.shared.emit(
                        LogEvent(
                            kind: .websocket,
                            direction: .inbound,
                            summary: "WS ← text \(s.prefix(80))\(s.count > 80 ? "…" : "")",
                            bodyPreview: s,
                            bodyIsTruncated: s.count > 10_000, 
                            tag: "WebSocket"
                        )
                    )
                case .data(let d):
                    LogTap.shared.emit(
                        LogEvent(
                            kind: .websocket,
                            direction: .inbound,
                            summary: "WS ← binary \(d.count) bytes",
                            bodyBytes: d.count,
                            tag: "WebSocket"
                        )
                    )
                @unknown default:
                    LogTap.shared.emit(
                        LogEvent(
                            kind: .websocket,
                            direction: .inbound,
                            summary: "WS ← (unknown message)", 
                            tag: "WebSocket"
                        )
                    )
                }
            case .failure(let err):
                LogTap.shared.emit(
                    LogEvent(
                        kind: .websocket,
                        direction: .error,
                        summary: "WS ERROR \(err.localizedDescription)",
                        reason: err.localizedDescription,
                        tag: "WebSocket"
                    )
                )
            }
            if self.isOpen { self.receiveLoop() }
        }
    }
}

/// Convenience factory
public func makeLoggedWebSocket(session: URLSession = .shared, url: URL) -> LogTapWebSocket {
    let task = session.webSocketTask(with: url)
    return LogTapWebSocket(task: task)
}
