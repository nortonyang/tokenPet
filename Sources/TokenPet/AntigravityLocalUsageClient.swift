import Foundation

struct AntigravityLocalUsageResult {
    let object: [String: Any]
    let endpointURL: URL
    let quotaSummary: [String: Any]?
    let quotaSummaryURL: URL?
}

enum AntigravityLocalUsageClient {
    private static let cache = AntigravityLocalUsageCache()
    private static let servicePrefix = "/exa.language_server_pb.LanguageServerService/"
    private static let userStatusPath = servicePrefix + "GetUserStatus"
    private static let quotaSummaryPath = servicePrefix + "RetrieveUserQuotaSummary"
    
    static func clearCache() {
        cache.store(nil)
    }
    
    static func cachedUserStatus() -> [String: Any]? {
        cache.value
    }
    
    static func fetchUserStatus() async -> AntigravityLocalUsageResult? {
        if let cached = cache.resultIfFresh(maxAge: 30) {
            return cached
        }
        
        for port in discoverHTTPPorts() {
            guard let url = URL(string: "http://127.0.0.1:\(port)\(userStatusPath)"),
                  var result = await requestUserStatus(url: url) else {
                continue
            }
            if let summaryURL = URL(string: "http://127.0.0.1:\(port)\(quotaSummaryPath)"),
               let summary = await requestJSON(url: summaryURL),
               summary["response"] is [String: Any] {
                result = AntigravityLocalUsageResult(
                    object: result.object,
                    endpointURL: result.endpointURL,
                    quotaSummary: summary,
                    quotaSummaryURL: summaryURL
                )
            }
            cache.store(result)
            return result
        }
        
        return nil
    }
    
    private static func discoverHTTPPorts() -> [Int] {
        let logDir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".gemini/antigravity-cli/log")
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: logDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        let recentLogs = files
            .filter { $0.lastPathComponent.hasPrefix("cli-") && $0.pathExtension == "log" }
            .compactMap { url -> (URL, Date)? in
                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                      values.isRegularFile == true else {
                    return nil
                }
                return (url, values.contentModificationDate ?? .distantPast)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(20)
            .map(\.0)
        
        var ports: [Int] = []
        var seen = Set<Int>()
        for url in recentLogs {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in content.split(separator: "\n").reversed() {
                guard line.contains("for HTTP"),
                      line.contains("Language server listening"),
                      let port = extractPort(from: String(line)),
                      seen.insert(port).inserted else {
                    continue
                }
                ports.append(port)
            }
        }
        
        return ports
    }
    
    private static func extractPort(from line: String) -> Int? {
        guard let range = line.range(of: #"port at\s+([0-9]+)\s+for HTTP"#, options: .regularExpression) else {
            return nil
        }
        let match = String(line[range])
        guard let portRange = match.range(of: #"[0-9]+"#, options: .regularExpression) else {
            return nil
        }
        return Int(match[portRange])
    }
    
    private static func requestUserStatus(url: URL) async -> AntigravityLocalUsageResult? {
        guard let object = await requestJSON(url: url),
              object["userStatus"] is [String: Any] else {
            return nil
        }
        return AntigravityLocalUsageResult(
            object: object,
            endpointURL: url,
            quotaSummary: nil,
            quotaSummaryURL: nil
        )
    }
    
    private static func requestJSON(url: URL) async -> [String: Any]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 1.5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = "{}".data(using: .utf8)
        
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }
}

private final class AntigravityLocalUsageCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cached: AntigravityLocalUsageResult?
    private var capturedAt: Date?
    
    var value: [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        return cached?.object
    }
    
    func resultIfFresh(maxAge: TimeInterval) -> AntigravityLocalUsageResult? {
        lock.lock()
        defer { lock.unlock() }
        guard let cached, let capturedAt, Date().timeIntervalSince(capturedAt) <= maxAge else {
            return nil
        }
        return cached
    }
    
    func store(_ result: AntigravityLocalUsageResult?) {
        lock.lock()
        cached = result
        capturedAt = result == nil ? nil : Date()
        lock.unlock()
    }
}
