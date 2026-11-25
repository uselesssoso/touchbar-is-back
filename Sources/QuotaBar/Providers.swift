import Foundation
import OSCrypt
import Security

enum CodexQuota {
    static let knownBinaries = [
        "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex"
    ]

    @MainActor
    static func read(into quotas: Quotas) async {
        guard let path = locateBinary() else {
            quotas.set("Codex", nil)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["app-server"]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            quotas.set("Codex", nil)
            return
        }

        let request = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"quotabar","version":"0.1.1"},"capabilities":{}}}
        {"jsonrpc":"2.0","method":"initialized","params":{}}
        {"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read","params":{}}

        """
        input.fileHandleForWriting.write(Data(request.utf8))
        // Keep stdin open until the rate-limit reply arrives. Closing it makes
        // app-server exit before it writes the id:2 result.

        let data = await readSome(from: output.fileHandleForReading, timeout: 8)
        try? input.fileHandleForWriting.close()
        process.terminate()

        guard let text = String(data: data, encoding: .utf8),
              let line = text.split(separator: "\n").first(where: { $0.contains("\"id\":2") }),
              let bytes = String(line).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              object["error"] == nil,
              let result = object["result"] as? [String: Any]
        else {
            quotas.set("Codex", nil)
            return
        }

        let limits = (result["rateLimits"] as? [String: Any]) ?? result
        let primary = (limits["primary"] as? [String: Any])
            ?? (limits["rateLimit"] as? [String: Any])
            ?? limits

        let used = usedFraction(from: primary)
        let reset = resetLabel(from: primary)
        if used == nil {
            quotas.set("Codex", nil)
        } else {
            quotas.set("Codex", used, reset)
        }
    }

    private static func locateBinary() -> String? {
        for path in knownBinaries where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for folder in pathEnv.split(separator: ":") {
            let candidate = "\(folder)/codex"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func usedFraction(from fields: [String: Any]) -> Double? {
        if let remaining = number(fields, "remainingPercent") {
            return 1 - remaining / 100
        }
        if let used = number(fields, "usedPercent") ?? number(fields, "usagePercent") {
            return used > 1 ? used / 100 : used
        }
        if let remaining = number(fields, "remaining"), let limit = number(fields, "limit"), limit > 0 {
            return 1 - remaining / limit
        }
        if let used = number(fields, "used"), let limit = number(fields, "limit"), limit > 0 {
            return used / limit
        }
        return nil
    }

    private static func resetLabel(from fields: [String: Any]) -> String? {
        if let text = fields["resetsAt"] as? String, !text.isEmpty { return text }
        if let text = fields["resetAt"] as? String, !text.isEmpty { return text }
        if let seconds = number(fields, "resetsAt") ?? number(fields, "resetAt") ?? number(fields, "nextResetTimestampUtc") {
            let date: Date
            if seconds > 10_000_000_000 {
                date = Date(timeIntervalSince1970: seconds / 1000)
            } else {
                date = Date(timeIntervalSince1970: seconds)
            }
            return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
        }
        return nil
    }

    private static func number(_ fields: [String: Any], _ key: String) -> Double? {
        (fields[key] as? NSNumber)?.doubleValue
    }

    private static func readSome(from handle: FileHandle, timeout: TimeInterval) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                var data = Data()
                let deadline = Date().addingTimeInterval(timeout)
                handle.readabilityHandler = { file in
                    data.append(file.availableData)
                    if data.contains(UInt8(ascii: "\n")), String(data: data, encoding: .utf8)?.contains("\"id\":2") == true {
                        file.readabilityHandler = nil
                    }
                }
                while Date() < deadline, handle.readabilityHandler != nil {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                handle.readabilityHandler = nil
                continuation.resume(returning: data)
            }
        }
    }
}

enum CursorSafeStorage {
    private static let service = "Cursor Safe Storage"
    private static let account = "Cursor Key"
    private static let prefix = "cursor-safe-storage:v1:"
    private static var cachedPassword: Data?

    static func openToken(_ raw: String, allowPrompt: Bool) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String
        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 {
            value = String(trimmed.dropFirst().dropLast())
        } else {
            value = trimmed
        }
        if value.hasPrefix(prefix) {
            return decrypt(value, allowPrompt: allowPrompt)
        }
        // Unknown sealed format: never send ciphertext as a credential.
        if value.hasPrefix("cursor-safe-storage:") {
            return nil
        }
        return value.isEmpty ? nil : value
    }

    private static func decrypt(_ sealed: String, allowPrompt: Bool) -> String? {
        let b64 = String(sealed.dropFirst(prefix.count))
        guard let envelope = Data(base64Encoded: b64), envelope.count > 3 else { return nil }
        let marker = Data("v10".utf8)
        guard envelope.starts(with: marker) else { return nil }
        let ciphertext = envelope.dropFirst(marker.count)
        guard let password = password(allowPrompt: allowPrompt) else { return nil }

        let plain: String? = password.withUnsafeBytes { passBuf in
            ciphertext.withUnsafeBytes { cipherBuf in
                guard let passPtr = passBuf.baseAddress, let cipherPtr = cipherBuf.baseAddress else { return nil }
                guard let cString = oscrypt_decrypt_v10(cipherPtr, ciphertext.count, passPtr, password.count) else {
                    return nil
                }
                defer { free(cString) }
                let text = String(cString: cString)
                return text.isEmpty ? nil : text
            }
        }
        guard let plain, looksLikeSession(plain) else { return nil }
        return plain
    }

    private static func looksLikeSession(_ text: String) -> Bool {
        if text.hasPrefix("cursor-safe-storage:") { return false }
        if text.contains("eyJ") || text.contains("::") { return true }
        return text.filter { $0 == "." }.count >= 2
    }

    private static func password(allowPrompt: Bool) -> Data? {
        if let cachedPassword, !cachedPassword.isEmpty { return cachedPassword }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if allowPrompt {
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIAllow
        } else {
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, !data.isEmpty else {
            return nil
        }
        cachedPassword = data
        return data
    }
}

private final class CursorAPISession: NSObject, URLSessionTaskDelegate {
    static let shared: URLSession = {
        let delegate = CursorAPISession()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        // Keep the delegate alive for the process; URLSession holds it weakly.
        _retained = delegate
        return session
    }()

    private static var _retained: CursorAPISession?

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let host = request.url?.host else {
            completionHandler(nil)
            return
        }
        let allowed = host == "cursor.com"
            || host == "www.cursor.com"
            || host == "api2.cursor.sh"
            || host.hasSuffix(".cursor.com")
            || host.hasSuffix(".cursor.sh")
        completionHandler(allowed ? request : nil)
    }
}

enum CursorSessionQuota {
    private static let databasePath = NSHomeDirectory() + "/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    private static let preferredKeys = [
        "cursorAuth/accessToken",
        "cursorAuth/cachedAccessToken"
    ]

    @MainActor
    static func read(into quotas: Quotas, allowKeychainPrompt: Bool) async {
        quotas.set("Cursor", nil)
        quotas.set("Grok Bot", nil)
        guard let token = sessionToken(allowKeychainPrompt: allowKeychainPrompt) else { return }

        async let cursorData = firstSuccess(cursorRequests(token))
        async let grokData = firstSuccess(grokRequests(token))

        if let json = await decode(cursorData) {
            apply(json, to: "Cursor", quotas: quotas)
        }
        if let json = await decode(grokData) {
            apply(json, to: "Grok Bot", quotas: quotas)
        }
    }

    private static func sessionToken(allowKeychainPrompt: Bool) -> String? {
        guard FileManager.default.fileExists(atPath: databasePath) else { return nil }
        // Read only specific known keys. The token stays in memory for the request and is never logged.
        let keyList = preferredKeys.map { "'\($0)'" }.joined(separator: ", ")
        let sql = "SELECT key, value FROM ItemTable WHERE key IN (\(keyList));"
        let rows = sqlite(sql)
        for key in preferredKeys {
            if let value = rows[key], !value.isEmpty,
               let token = CursorSafeStorage.openToken(value, allowPrompt: allowKeychainPrompt) {
                return token
            }
        }
        return nil
    }

    private static func sqlite(_ sql: String) -> [String: String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-separator", "\t", databasePath, sql]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return [:]
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else {
            return [:]
        }
        var rows: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            if fields.count == 2 {
                rows[String(fields[0])] = String(fields[1])
            }
        }
        return rows
    }

    private static func cursorRequests(_ token: String) -> [URLRequest] {
        var requests: [URLRequest] = []
        if let url = URL(string: "https://cursor.com/api/usage-summary") {
            requests.append(contentsOf: authenticated(url, token: token, method: "GET"))
        }
        if let url = URL(string: "https://www.cursor.com/api/usage-summary") {
            requests.append(contentsOf: authenticated(url, token: token, method: "GET"))
        }
        if let url = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage") {
            requests.append(contentsOf: authenticated(url, token: token, method: "POST", body: Data("{}".utf8)))
        }
        return requests
    }

    private static func grokRequests(_ token: String) -> [URLRequest] {
        var requests: [URLRequest] = []
        if let url = URL(string: "https://cursor.com/api/dashboard/get-sand-usage-status") {
            requests.append(contentsOf: authenticated(url, token: token, method: "POST", body: Data("{}".utf8)))
            requests.append(contentsOf: authenticated(url, token: token, method: "GET"))
        }
        if let url = URL(string: "https://www.cursor.com/api/dashboard/get-sand-usage-status") {
            requests.append(contentsOf: authenticated(url, token: token, method: "POST", body: Data("{}".utf8)))
        }
        return requests
    }

    private static func authenticated(_ url: URL, token: String, method: String, body: Data? = nil) -> [URLRequest] {
        func base() -> URLRequest {
            var request = URLRequest(url: url, timeoutInterval: 8)
            request.httpMethod = method
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
            request.setValue("https://cursor.com/dashboard", forHTTPHeaderField: "Referer")
            request.httpBody = body
            return request
        }
        var requests: [URLRequest] = []
        var bearer = base()
        bearer.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        requests.append(bearer)
        var cookie = base()
        cookie.setValue("WorkosCursorSessionToken=\(token)", forHTTPHeaderField: "Cookie")
        requests.append(cookie)
        if token.contains("::") {
            var encoded = base()
            let value = token.replacingOccurrences(of: "::", with: "%3A%3A")
            encoded.setValue("WorkosCursorSessionToken=\(value)", forHTTPHeaderField: "Cookie")
            requests.append(encoded)
        }
        return requests
    }

    private static func firstSuccess(_ requests: [URLRequest]) async -> Data? {
        for request in requests {
            if let (data, response) = try? await CursorAPISession.shared.data(for: request),
               let http = response as? HTTPURLResponse,
               http.statusCode == 200,
               !data.isEmpty {
                return data
            }
        }
        return nil
    }

    private static func decode(_ data: Data?) -> [String: Any]? {
        guard let data, let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let dictionary = object as? [String: Any] { return dictionary }
        return nil
    }

    @MainActor
    private static func apply(_ json: [String: Any], to id: String, quotas: Quotas) {
        let nested = (json["usage"] as? [String: Any]) ?? json
        let used = usedFraction(from: nested) ?? usedFraction(from: json)
        let reset = resetLabel(from: nested) ?? resetLabel(from: json)
        quotas.set(id, used, reset)
    }

    private static func usedFraction(from fields: [String: Any]) -> Double? {
        if let remaining = number(fields, "remainingPercent") {
            return 1 - remaining / 100
        }
        if let used = number(fields, "usedPercent") ?? number(fields, "usagePercent") {
            return used > 1 ? used / 100 : used
        }
        return nil
    }

    private static func resetLabel(from fields: [String: Any]) -> String? {
        for key in ["resetAt", "resetsAt", "nextResetTimestampUtc", "reset_at"] {
            if let text = fields[key] as? String, !text.isEmpty { return text }
            if let seconds = number(fields, key) {
                let date = seconds > 10_000_000_000
                    ? Date(timeIntervalSince1970: seconds / 1000)
                    : Date(timeIntervalSince1970: seconds)
                return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
            }
        }
        return nil
    }

    private static func number(_ fields: [String: Any], _ key: String) -> Double? {
        (fields[key] as? NSNumber)?.doubleValue
    }
}
