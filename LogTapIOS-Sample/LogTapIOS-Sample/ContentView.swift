//
//  ContentView.swift
//  LogTapIOS-Sample
//
//  Clean, modular playground to generate Logger / HTTP / WebSocket traffic
//

import SwiftUI
import LogTapIOS

// MARK: - Pressable Button Style for better affordance
struct TapButtonStyle: ButtonStyle {
    enum Kind { case prominent, bordered }
    var kind: Kind = .bordered

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(background(configuration))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(borderColor(configuration), lineWidth: kind == .prominent ? 0 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.9), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .hoverEffect(.highlight)
            .accessibilityAddTraits(.isButton)
    }

    private func background(_ configuration: Configuration) -> some View {
        Group {
            switch kind {
            case .prominent:
                (configuration.isPressed ? Color.accentColor.opacity(0.85) : Color.accentColor)
            case .bordered:
                (configuration.isPressed ? Color.secondary.opacity(0.18) : Color.secondary.opacity(0.12))
            }
        }
    }

    private func borderColor(_ configuration: Configuration) -> Color {
        switch kind {
        case .prominent:
            return .clear
        case .bordered:
            return configuration.isPressed ? .accentColor.opacity(0.6) : .secondary.opacity(0.35)
        }
    }
}

// MARK: - Intercepted URLSession (uses LogTapURLProtocol)
private let tapSession: URLSession = {
    let cfg = URLSessionConfiguration.default
    cfg.protocolClasses = [LogTapURLProtocol.self] + (cfg.protocolClasses ?? [])
    cfg.waitsForConnectivity = true
    cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
    cfg.timeoutIntervalForRequest = 30
    cfg.timeoutIntervalForResource = 60
    return URLSession(configuration: cfg)
}()

// MARK: - Endpoints & Samples
private enum API {
    static let users       = URL(string: "https://fakestoreapi.com/users")!
    static let login       = URL(string: "https://fakestoreapi.com/auth/login")!
    static let user1       = URL(string: "https://fakestoreapi.com/users/1")!
    static let http404     = URL(string: "https://httpbin.org/status/404")!
    static let http500     = URL(string: "https://httpbin.org/status/500")!
    static let httpDelay3  = URL(string: "https://httpbin.org/delay/3")!
    static let headers     = URL(string: "https://httpbin.org/headers")!
    static let jsonBig     = URL(string: "https://httpbin.org/json")!
    static let gzip        = URL(string: "https://httpbin.org/gzip")!
}

private enum Samples {
    static let loginBody: [String: Any] = ["username": "mor_2314", "password": "83r5^"]
    static let userPatch: [String: Any] = ["name": "John", "role": "tester"]
    static let wsEchoURL = URL(string: "wss://echo.websocket.org")!
    static let wsMessage = "{\"hello\":\"world\",\"platform\":\"iOS\"}"
}

// MARK: - ViewModel
@MainActor
final class PlaygroundVM: ObservableObject {
    // WebSocket state
    @Published var wsConnected = false
    @Published var wsLastEvent = "—"

    private var ws: URLSessionWebSocketTask?
    private let wsSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg)
    }()

    // MARK: Logger
    func logAllLevels() {
        logV("VERBOSE sample log")
        logD("DEBUG sample log")
        logI("INFO sample log")
        logW("WARN sample log")
        logE("ERROR sample log")
    }

    // MARK: HTTP helpers
    func get(_ url: URL) { request(url: url, method: "GET") }
    func delete(_ url: URL) { request(url: url, method: "DELETE") }

    func postJSON(_ url: URL, body: [String: Any]) { request(url: url, method: "POST", json: body) }
    func putJSON(_ url: URL, body: [String: Any]) { request(url: url, method: "PUT", json: body) }

    private func request(url: URL, method: String, json: [String: Any]? = nil, extraHeaders: [String:String] = [:]) {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        extraHeaders.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let json { do { req.httpBody = try JSONSerialization.data(withJSONObject: json) ; req.setValue("application/json", forHTTPHeaderField: "Content-Type") } catch { logE("Encode error: \(error.localizedDescription)"); return } }

        logD("HTTP \(method) → \(url.absoluteString)")
        tapSession.dataTask(with: req) { data, resp, err in
            if let err = err { logE("HTTP \(method) error: \(err.localizedDescription)"); return }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            if let data, let body = String(data: data, encoding: .utf8) {
                logD("HTTP \(method) ← \(code) bytes=\(data.count)\n\(body)")
            } else {
                logD("HTTP \(method) ← \(code) (no body)")
            }
        }.resume()
    }

    // MARK: WebSocket helpers
    func wsConnect(_ url: URL) {
        ws?.cancel(with: .goingAway, reason: nil)
        let task = wsSession.webSocketTask(with: url)
        ws = task
        task.resume()
        wsConnected = true
        wsLastEvent = "Connecting…"
        logI("WS connecting → \(url.absoluteString)")
        receiveLoop()
    }

    func wsSend(_ text: String) {
        guard let ws else { logE("WS not connected"); return }
        logD("WS → send: \(text)")
        ws.send(.string(text)) { [weak self] err in
            if let err { self?.wsLastEvent = "Send error: \(err.localizedDescription)"; logE("WS send error: \(err.localizedDescription)") }
        }
    }

    func wsDisconnect() {
        ws?.cancel(with: .goingAway, reason: nil)
        ws = nil
        wsConnected = false
        wsLastEvent = "Disconnected"
        logI("WS disconnected")
    }

    private func receiveLoop() {
        guard let ws else { return }
        ws.receive { [weak self] result in
            switch result {
            case .failure(let err):
                self?.wsLastEvent = "Receive error: \(err.localizedDescription)"
                self?.wsConnected = false
                logE("WS receive error: \(err.localizedDescription)")
            case .success(let msg):
                switch msg {
                case .string(let text):
                    self?.wsLastEvent = "← text (\(text.count))"
                    logD("WS ← text: \(text)")
                case .data(let data):
                    self?.wsLastEvent = "← binary (\(data.count) bytes)"
                    logD("WS ← binary (\(data.count) bytes)")
                @unknown default:
                    self?.wsLastEvent = "← unknown"
                    logW("WS ← unknown message")
                }
                self?.receiveLoop() // keep listening
            }
        }
    }
}

// MARK: - SwiftUI
struct ContentView: View {
    var body: some View { LogTapPlaygroundScreen() }
}

struct LogTapPlaygroundScreen: View {
    @StateObject private var vm = PlaygroundVM()

    // Adaptive grid for nice wrapping on all devices
    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                sectionLogger
                sectionHTTPBasics
                sectionHTTPEdge
                sectionWebSocket
            }
            .padding(16)
        }
    }

    // MARK: Sections
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LogTap Playground").font(.title)
            Text("Generate Logger, HTTP, and WebSocket events to see them in LogTap’s web UI.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var sectionLogger: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Logger").font(.headline)
            LazyVGrid(columns: columns, spacing: 12) {
                Button("Log ALL levels") { vm.logAllLevels() }
                Button("VERBOSE") { logV("VERBOSE sample log") }
                Button("DEBUG")   { logD("DEBUG sample log") }
                Button("INFO")    { logI("INFO sample log") }
                Button("WARN")    { logW("WARN sample log") }
                Button("ERROR")   { logE("ERROR sample log") }
            }.buttonStyle(TapButtonStyle(kind: .prominent))
        }
    }

    private var sectionHTTPBasics: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HTTP – Basics").font(.headline)
            LazyVGrid(columns: columns, spacing: 12) {
                Button("GET users") { vm.get(API.users) }
                Button("POST login") { vm.postJSON(API.login, body: Samples.loginBody) }
                Button("PUT user") { vm.putJSON(API.user1, body: Samples.userPatch) }
                Button("DELETE user") { vm.delete(API.user1) }
            }.buttonStyle(TapButtonStyle(kind: .bordered))
        }
    }

    private var sectionHTTPEdge: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HTTP – Edge cases").font(.headline)
            LazyVGrid(columns: columns, spacing: 12) {
                Button("GET 404") { vm.get(API.http404) }
                Button("GET 500") { vm.get(API.http500) }
                Button("GET delay 3s") { vm.get(API.httpDelay3) }
                Button("GET headers") { vm.get(API.headers) }
                Button("GET json big") { vm.get(API.jsonBig) }
                Button("GET gzip") { vm.get(API.gzip) }
            }.buttonStyle(TapButtonStyle(kind: .bordered))
        }
    }

    private var sectionWebSocket: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WebSocket").font(.headline)
            HStack(spacing: 12) {
                Button(vm.wsConnected ? "Disconnect" : "Connect") {
                    if vm.wsConnected { vm.wsDisconnect() } else { vm.wsConnect(Samples.wsEchoURL) }
                }
                Button("Send JSON") { vm.wsSend(Samples.wsMessage) }
            }
            .buttonStyle(TapButtonStyle(kind: .prominent))
            Text("State: \(vm.wsConnected ? "Connected" : "Idle")  ·  Last: \(vm.wsLastEvent)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview
#Preview {
    LogTapPlaygroundScreen()
}
