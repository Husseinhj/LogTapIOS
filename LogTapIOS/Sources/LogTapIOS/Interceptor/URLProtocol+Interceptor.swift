//
//  URLProtocol+Interceptor.swift
//  LogTapIOS
//
//  Created by Hussein Habibi Juybari on 06.09.25.
//

import Foundation

/// Intercepts URLSession traffic (HTTP/HTTPS) when its configuration includes this protocol.
public final class LogTapURLProtocol: URLProtocol, URLSessionDataDelegate {
    private var relayTask: URLSessionDataTask?
    private var relaySession: URLSession?
    private var resp: URLResponse?
    private var data = Data()
    private var startedAt: CFAbsoluteTime = 0
    
    public override class func canInit(with request: URLRequest) -> Bool {
        // Avoid loops: respect our marker
        if URLProtocol.property(forKey: "LogTapHandled", in: request) as? Bool == true { return false }
        // Only HTTP/HTTPS
        return (request.url?.scheme == "http" || request.url?.scheme == "https")
    }
    
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    
    public override func startLoading() {
        startedAt = CFAbsoluteTimeGetCurrent()
        var r = (self.request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty(true, forKey: "LogTapHandled", in: r)
        
        // Log request
        let bodyPreview: String?
        if let body = r.httpBody, !body.isEmpty {
            bodyPreview = LogTap.makeBodyPreview(data: body, contentType: r.value(forHTTPHeaderField: "Content-Type"))
        } else if let stream = r.httpBodyStream {
            // read stream (copy)
            let copied = LogTap.readStream(stream, maxBytes: LogTap.shared.config.maxBodyBytes)
            bodyPreview = LogTap.makeBodyPreview(data: copied, contentType: r.value(forHTTPHeaderField: "Content-Type"))
        } else {
            bodyPreview = nil
        }
        
        LogTap.shared.emit(
            LogEvent(
                kind: .http,
                direction: .request,
                summary: "→ \(r.httpMethod ?? "GET") \(r.url?.absoluteString ?? "")",
                url: r.url?.absoluteString,
                method: r.httpMethod,
                headers: r.allHTTPHeaderFields.map { d in d.reduce(into: [:]) { $0[$1.key] = [$1.value] } },
                bodyPreview: bodyPreview,
                bodyIsTruncated: false,
                tag: "HTTP"
            )
        )
        
        // Create a “passthrough” task
        let cfg = URLSessionConfiguration.default
        cfg.protocolClasses = []
        let session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        relaySession = session
        relayTask = session.dataTask(with: r as URLRequest)
        relayTask?.resume()
    }
    
    public override func stopLoading() {
        relayTask?.cancel()
        relaySession?.invalidateAndCancel()
    }
    
    // MARK: URLSessionDataDelegate
    
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        resp = response
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        completionHandler(.allow)
    }
    
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        self.data.append(data)
        client?.urlProtocol(self, didLoad: data)
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let tookMs = Int64((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
        defer { client?.urlProtocolDidFinishLoading(self) }
        
        if let error = error {
            LogTap.shared.emit(
                LogEvent(
                    kind: .http,
                    direction: .error,
                    summary: "HTTP ERROR \(self.request.httpMethod ?? "") \(self.request.url?.absoluteString ?? "") — \(error.localizedDescription)",
                    url: self.request.url?.absoluteString,
                    method: self.request.httpMethod,
                    reason: error.localizedDescription, 
                    tag: "HTTP"
                )
            )
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        
        let httpResp = resp as? HTTPURLResponse
        let bodyPreview = LogTap.makeBodyPreview(data: data, contentType: httpResp?.value(forHTTPHeaderField: "Content-Type"))
        LogTap.shared.emit(
            LogEvent(
                kind: .http,
                direction: .response,
                summary: "← \(httpResp?.statusCode ?? 0) \(HTTPURLResponse.localizedString(forStatusCode: httpResp?.statusCode ?? 0)) (\(tookMs)ms) \(self.request.httpMethod ?? "") \(self.request.url?.absoluteString ?? "")",
                url: self.request.url?.absoluteString,
                method: self.request.httpMethod,
                status: httpResp?.statusCode,
                headers: httpResp?.allHeaderFields.reduce(into: [:], { acc, kv in
                    if let k = kv.key as? String, let v = kv.value as? String {
                        acc[k] = [v]
                    }
                }
                                                         ),
                bodyPreview: bodyPreview,
                bodyBytes: data.count,
                tookMs: tookMs,
                tag: "HTTP",
            )
        )
    }
}
