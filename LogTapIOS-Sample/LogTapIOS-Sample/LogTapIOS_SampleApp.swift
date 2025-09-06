//
//  LogTapIOS_SampleApp.swift
//  LogTapIOS-Sample
//
//  Created by Hussein Habibi Juybari on 06.09.25.
//


import SwiftUI
import LogTapIOS

@main
struct LogTapIOS_SampleApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Start LogTap server (DEBUG suggested)
        var cfg = LogTap.Config()
        cfg.port = 8795
        cfg.capacity = 5000
        cfg.enableOnRelease = false
        LogTap.shared.start(cfg)

        // Logger configuration
        #if DEBUG
        let sink = LogTapSinkAdapter()
        LogTapPrintBridge.shared.start(sink: sink)
        
        LogTapLogger.shared.debugMode = true
        LogTapLogger.shared.allowReleaseLogging = false
        LogTapLogger.shared.minLevel = .verbose
        
        #else
        LogTapLogger.shared.debugMode = false
        LogTapLogger.shared.allowReleaseLogging = false
        LogTapLogger.shared.minLevel = .warn
        #endif

        // Print helpful boot URL(s)
        let urls = LogTap.shared.urls().joined(separator: ", ")
        logD("LogTap server ready at \(urls)")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Kick off some sample traffic so you can see logs immediately
                .task { await runSampleTraffic() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                logI("App became active")
            }
        }
    }
}


/// Builds a URLSession that routes requests through LogTapURLProtocol so they get logged
func makeLoggedSession() -> URLSession {
    let cfg = URLSessionConfiguration.default
    // Prepend our protocol so it gets first crack at handling requests
    cfg.protocolClasses = [LogTapURLProtocol.self] + (cfg.protocolClasses ?? [])
    return URLSession(configuration: cfg)
}

// MARK: - Samples
private extension LogTapIOS_SampleApp {
    func makeSession() -> URLSession {
        // URLSession that routes through LogTapURLProtocol
        makeLoggedSession()
    }

    func runSampleTraffic() async {
        
        let session = makeSession()

        // GET
        if let url = URL(string: "https://httpbin.org/get") {
            _ = try? await session.data(from: url)
        }

        // POST (JSON)
        if let url = URL(string: "https://httpbin.org/post") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = #"{"hello":"world","platform":"iOS","ts":\#(Date().timeIntervalSince1970)}"#.data(using: .utf8)
            _ = try? await session.data(for: req)
        }

        // DELETE
        if let url = URL(string: "https://httpbin.org/delete") {
            var req = URLRequest(url: url)
            req.httpMethod = "DELETE"
            _ = try? await session.data(for: req)
        }

        // WebSocket echo demo
        if let url = URL(string: "wss://echo.websocket.org") {
            let ws = makeLoggedWebSocket(url: url)
            ws.resume()
            ws.send("hello from LogTap iOS")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                ws.cancel()
            }
        }

        // Logger samples
        logV("Verbose example")
        logD("Debug example")
        logI("Info example")
        logW("Warn example")
        logE("Error example")
    }
}
