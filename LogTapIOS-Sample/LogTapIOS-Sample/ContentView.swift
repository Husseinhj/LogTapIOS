//
//  ContentView.swift
//  LogTapIOS-Sample
//
//  Created by Hussein Habibi Juybari on 06.09.25.
//

import SwiftUI
import LogTapIOS

private let tapSession: URLSession = {
    let cfg = URLSessionConfiguration.default
    // Prepend our interceptor so it sees requests first
    cfg.protocolClasses = [LogTapURLProtocol.self] + (cfg.protocolClasses ?? [])
    cfg.waitsForConnectivity = true
    cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: cfg)
}()

struct ContentView: View {
    var body: some View {
        LogTapPlaygroundScreen()
    }
}

struct LogTapPlaygroundScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("LogTap Playground")
                    .font(.title)
                Text("Hello iOS! Use these to generate HTTP, WebSocket, and Logger events.")
                    .font(.subheadline)

                // Logger section
                Text("Logger")
                    .font(.headline)
                HStack(spacing: 12) {
                    Button("Log VERBOSE") { logV("VERBOSE sample log") }
                    Button("Log DEBUG") { logD("DEBUG sample log") }
                    Button("Log INFO") { logI("INFO sample log") }
                    Button("Log WARN") { logW("WARN sample log") }
                    Button("Log ERROR") { logE("ERROR sample log") }
                }

                // HTTP section
                Text("HTTP – Basics")
                    .font(.headline)
                HStack(spacing: 12) {
                    Button("GET users") {
                        httpGet("https://fakestoreapi.com/users")
                    }
                    Button("POST login") {
                        httpPostJson("https://fakestoreapi.com/auth/login", body: ["username": "mor_2314", "password": "83r5^_"])
                    }
                    Button("PUT user") {
                        httpPutJson("https://fakestoreapi.com/users/1", body: ["name": "John"])
                    }
                    Button("DELETE user") {
                        httpDelete("https://fakestoreapi.com/users/1")
                    }
                }

                // WebSocket section
                Text("WebSocket")
                    .font(.headline)
                HStack(spacing: 12) {
                    Button("WS connect") {
                        openEchoWebSocket("wss://echo.websocket.org")
                    }
                    Button("WS connect & send") {
                        openEchoWebSocketAndSend("wss://echo.websocket.org", message: "Hello from iOS!")
                    }
                }
            }
            .padding()
        }
    }
}

func httpGet(_ url: String) {
    guard let u = URL(string: url) else { logE("Invalid URL: \(url)"); return }
    var req = URLRequest(url: u)
    req.httpMethod = "GET"
    req.addValue("application/json", forHTTPHeaderField: "Accept")

    logD("HTTP GET → \(url)")
    tapSession.dataTask(with: req) { data, resp, err in
        if let err = err { logE("HTTP GET error: \(err.localizedDescription)"); return }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        if let data = data, let body = String(data: data, encoding: .utf8) {
            logD("HTTP GET ← \(code) bytes=\(data.count)\n\(body)")
        } else {
            logD("HTTP GET ← \(code) (no body)")
        }
    }.resume()
}
func httpPostJson(_ url: String, body: [String: Any]) {
    guard let u = URL(string: url) else { logE("Invalid URL: \(url)"); return }
    var req = URLRequest(url: u)
    req.httpMethod = "POST"
    req.addValue("application/json", forHTTPHeaderField: "Content-Type")
    req.addValue("application/json", forHTTPHeaderField: "Accept")
    do { req.httpBody = try JSONSerialization.data(withJSONObject: body, options: []) }
    catch { logE("POST encode error: \(error.localizedDescription)"); return }

    logD("HTTP POST → \(url) body=\(body)")
    tapSession.dataTask(with: req) { data, resp, err in
        if let err = err { logE("HTTP POST error: \(err.localizedDescription)"); return }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        if let data = data, let bodyStr = String(data: data, encoding: .utf8) {
            logD("HTTP POST ← \(code) bytes=\(data.count)\n\(bodyStr)")
        } else { logD("HTTP POST ← \(code) (no body)") }
    }.resume()
}
func httpPutJson(_ url: String, body: [String: Any]) {
    guard let u = URL(string: url) else { logE("Invalid URL: \(url)"); return }
    var req = URLRequest(url: u)
    req.httpMethod = "PUT"
    req.addValue("application/json", forHTTPHeaderField: "Content-Type")
    req.addValue("application/json", forHTTPHeaderField: "Accept")
    do { req.httpBody = try JSONSerialization.data(withJSONObject: body, options: []) }
    catch { logE("PUT encode error: \(error.localizedDescription)"); return }

    logD("HTTP PUT → \(url) body=\(body)")
    tapSession.dataTask(with: req) { data, resp, err in
        if let err = err { logE("HTTP PUT error: \(err.localizedDescription)"); return }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        if let data = data, let bodyStr = String(data: data, encoding: .utf8) {
            logD("HTTP PUT ← \(code) bytes=\(data.count)\n\(bodyStr)")
        } else { logD("HTTP PUT ← \(code) (no body)") }
    }.resume()
}
func httpDelete(_ url: String) {
    guard let u = URL(string: url) else { logE("Invalid URL: \(url)"); return }
    var req = URLRequest(url: u)
    
    req.httpMethod = "DELETE"
    req.addValue("application/json", forHTTPHeaderField: "Accept")

    logD("HTTP DELETE → \(url)")
    tapSession.dataTask(with: req) { data, resp, err in
        if let err = err { logE("HTTP DELETE error: \(err.localizedDescription)"); return }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        if let data = data, let bodyStr = String(data: data, encoding: .utf8) {
            logD("HTTP DELETE ← \(code) bytes=\(data.count)\n\(bodyStr)")
        } else { logD("HTTP DELETE ← \(code) (no body)") }
    }.resume()
}

private var wsSession: URLSession = {
    let cfg = URLSessionConfiguration.default
    cfg.waitsForConnectivity = true
    return URLSession(configuration: cfg)
}()
private var wsTask: URLSessionWebSocketTask?

func openEchoWebSocket(_ url: String) {
    print("=====> openEchoWebSocket(\(url)) =======")
    guard let u = URL(string: url) else { logE("Invalid WS URL: \(url)"); return }
    wsTask?.cancel(with: .goingAway, reason: nil)
    let task = wsSession.webSocketTask(with: u)
    wsTask = task
    task.resume()
    logI("WS connecting → \(url)")
    
    // Start receive loop
    func receiveOnce() {
        task.receive { result in
            switch result {
            case .failure(let err):
                logE("WS receive error: \(err.localizedDescription)")
            case .success(let msg):
                switch msg {
                case .string(let text): logD("WS ← text: \(text)")
                case .data(let data):   logD("WS ← binary (\(data.count) bytes)")
                @unknown default:       logW("WS ← unknown message")
                }
                receiveOnce() // loop
            }
        }
    }
    receiveOnce()
}
func openEchoWebSocketAndSend(_ url: String, message: String) {
    openEchoWebSocket(url)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
        guard let task = wsTask else { logE("WS task not ready"); return }
        logD("WS → send: \(message)")
        task.send(.string(message)) { err in
            if let err = err { logE("WS send error: \(err.localizedDescription)") }
        }
        task.sendPing { err in if let err = err { logW("WS ping error: \(err.localizedDescription)") } }
    }
}
