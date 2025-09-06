# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),  
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.1.0] - 2025-09-07
### Added
- Initial release of **LogTap** for iOS/macOS/iPadOS.
- Core **LogTapServer** implementation with embedded SwiftNIO server.
- **Logger**:
  - Capture standard logs with levels: VERBOSE, DEBUG, INFO, WARN, ERROR, ASSERT.
  - `LogTapPrintBridge` for redirecting `print` output into LogTap.
- **Interceptor**:
  - `LogTapURLProtocol` for capturing HTTP(S) requests and responses automatically.
- **WebSocket Logger**:
  - Real-time capture of WebSocket messages (send/receive, ping/pong/close).
- **Web UI Viewer**:
  - Material 3–inspired design with selectable themes (Android Studio, Xcode, VS Code, Grafana).
  - Persistent theme and layout preferences.
  - Filter panel with column toggles, status filters, and level filters.
  - Stats chips for quick filtering (Total, HTTP, WS, Log, GET, POST).
  - Drawer panel with detailed request/response/headers and JSON syntax highlighting.
  - Export logs as JSON or HTML reports.
- **Multi-platform support**:
  - iOS, macOS, and iPadOS targets via Swift Package Manager (SPM).

---

## Notes
- This is the **first public version**. Expect API and UI refinements in upcoming releases.
- Feedback and contributions are welcome!
