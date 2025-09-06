// The Swift Programming Language
// https://docs.swift.org/swift-book
import Foundation
import NIO
import NIOHTTP1
import NIOTransportServices

public final class LogTap {
    public struct Config {
        public var port: Int = 8790
        public var capacity: Int = 5000
        public var maxBodyBytes: Int = 64_000
        public var redactHeaders: Set<String> = ["Authorization", "Cookie", "Set-Cookie"]
        public var enableOnRelease: Bool = false
        
        public init() {}
    }
    
    public static let shared = LogTap()
    private init() {}
    
    public private(set) var config = Config()
    private var server = LogTapServer()
    internal var store = LogTapStore(capacity: 5000)
    
    // MARK: Lifecycle
    
    public func start(_ cfg: Config = Config()) {
        self.config = cfg
        self.store = LogTapStore(capacity: cfg.capacity)
        
        print("----->>>>> start called <<<<<-----")
        // Router closure: serve UI, API, and WS
        let router: (HTTPRequestHead, ByteBuffer?) -> (status: HTTPResponseStatus, headers: HTTPHeaders, body: ByteBuffer?, upgradeToWebSocket: Bool) = { head, body in
            let path = URLComponents(string: head.uri)?.path ?? head.uri
            switch (head.method, path) {
            case (.GET, "/"):
                var bb = ByteBufferAllocator().buffer(capacity: Resources.indexHtml.utf8.count)
                bb.writeString(Resources.indexHtml)
                var h = HTTPHeaders()
                h.add(name: "Content-Type", value: "text/html; charset=utf-8")
                h.add(name: "Content-Length", value: String(bb.readableBytes))
                return (.ok, h, bb, false)
                
            case (.GET, "/app.css"):
                var bb = ByteBufferAllocator().buffer(capacity: Resources.appCss.utf8.count)
                bb.writeString(Resources.appCss)
                var h = HTTPHeaders()
                h.add(name: "Content-Type", value: "text/css; charset=utf-8")
                h.add(name: "Content-Length", value: String(bb.readableBytes))
                return (.ok, h, bb, false)
                
            case (.GET, "/app.js"):
                var bb = ByteBufferAllocator().buffer(capacity: Resources.appJs.utf8.count)
                bb.writeString(Resources.appJs)
                var h = HTTPHeaders()
                h.add(name: "Content-Type", value: "application/javascript; charset=utf-8")
                h.add(name: "Content-Length", value: String(bb.readableBytes))
                return (.ok, h, bb, false)
                
            case (.GET, "/api/logs"):
                let comps = URLComponents(string: head.uri)
                let sinceId = comps?.queryItems?.first(where: {$0.name == "sinceId"})?.value.flatMap(Int64.init)
                let limit = comps?.queryItems?.first(where: {$0.name == "limit"})?.value.flatMap(Int.init) ?? 500
                let list = self.store.snapshot(sinceId: sinceId, limit: limit)
                let data = try! JSONEncoder().encode(list)
                var bb = ByteBufferAllocator().buffer(capacity: data.count)
                bb.writeBytes(data)
                var h = HTTPHeaders()
                h.add(name: "Content-Type", value: "application/json; charset=utf-8")
                h.add(name: "Content-Length", value: String(bb.readableBytes))
                return (.ok, h, bb, false)
                
            case (.POST, "/api/clear"):
                var bb = ByteBufferAllocator().buffer(capacity: 2)
                bb.writeString("ok")
                var h = HTTPHeaders()
                h.add(name: "Content-Type", value: "text/plain; charset=utf-8")
                h.add(name: "Content-Length", value: String(bb.readableBytes))
                return (.ok, h, bb, false)
                
            case (.GET, "/ws"):
                // upgrade handled by pipeline; nothing to write here
                return (.switchingProtocols, .init(), nil, true)
                
            default:
                var h = HTTPHeaders()
                var bb = ByteBufferAllocator().buffer(capacity: 9)
                bb.writeString("Not Found")
                h.add(name: "Content-Type", value: "text/plain")
                h.add(name: "Content-Length", value: String(bb.readableBytes))
                return (.notFound, h, bb, false)
            }
        }
        
        try? server.start(port: cfg.port, router: router)
        
        // Broadcast on new events
        _ = store.subscribe { [weak self] ev in
            self?.server.broadcast(event: ev)
        }
        
        // helpful boot log
        let urls = self.urls()
        LogTapLogger.shared.d("LogTap server ready at \(urls.joined(separator: ", "))")
    }
    
    public func stop() {
        server.stop()
    }
    
    // MARK: Emit
    
    func emit(_ ev: LogEvent) {
        store.add(ev)
    }
    
    // MARK: Helpers
    
    static func makeBodyPreview(data: Data?, contentType: String?) -> String? {
        guard let data, !data.isEmpty else { return nil }
        if let ct = contentType?.lowercased(), ct.contains("application/json") {
            if let obj = try? JSONSerialization.jsonObject(with: data),
               let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .prettyPrinted]),
               let str = String(data: pretty, encoding: .utf8) {
                return str
            }
        }
        return String(data: data.prefix(64_000), encoding: .utf8) ??
        "(\(data.count) bytes binary)"
    }
    
    static func readStream(_ stream: InputStream, maxBytes: Int) -> Data {
        stream.open()
        defer { stream.close() }
        let bufSize = 16 * 1024
        var data = Data()
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate() }
        while stream.hasBytesAvailable && data.count < maxBytes {
            let read = stream.read(buf, maxLength: min(bufSize, maxBytes - data.count))
            if read <= 0 { break }
            data.append(buf, count: read)
        }
        return data
    }
    
    public func urls() -> [String] {
        // best-effort LAN IPv4 list
        var addrs: [String] = []
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr {
            var ptr: UnsafeMutablePointer<ifaddrs>? = first
            while ptr != nil {
                let ifa = ptr!.pointee
                if let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) {
                    var addr = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(ifa.ifa_addr, socklen_t(ifa.ifa_addr.pointee.sa_len), &addr, socklen_t(addr.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: addr)
                        if ip != "127.0.0.1" { addrs.append(ip) }
                    }
                }
                ptr = ifa.ifa_next
            }
            freeifaddrs(first)
        }
        return addrs.map { "http://\($0):\(config.port)/" }
    }
}
