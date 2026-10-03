import Foundation

enum CloudHTTP {
    static let referer = "https://github.com/Aayush9029/petal"

    static func request(
        _ url: URL,
        method: String = "POST",
        headers: [String: String] = [:],
        body: JSONValue? = nil,
        timeout: TimeInterval = 30
    ) throws -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try body.encoded()
        }
        return request
    }

    static func timeout(for tools: Set<CloudTool>) -> TimeInterval {
        tools.contains(.webSearch) ? 60 : 30
    }

    static func errorMessage(from data: Data) -> String? {
        if let json = try? JSONValue.decode(data) {
            let candidates: [JSONValue?] = [json["error"]?["message"], json["error"], json["message"]]
            if let message = candidates.lazy.compactMap({ $0?.stringValue }).first {
                return message
            }
        }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(200))
    }
}
