import Foundation

struct DPTDocument: Identifiable, Hashable {
    let id: String
    let path: String
    let currentPage: Int
    let totalPages: Int
    let modifiedDate: Date?

    var name: String { path.split(separator: "/").last.map(String.init) ?? path }
}

enum DPTError: LocalizedError {
    case invalidAddress
    case invalidResponse
    case request(String)
    case crypto
    case noDocument

    var errorDescription: String? {
        switch self {
        case .invalidAddress: "设备地址无效"
        case .invalidResponse: "DPT 返回了无效数据"
        case .request(let message): message
        case .crypto: "配对验证失败"
        case .noDocument: "请先选择正在阅读的文档"
        }
    }
}

private final class TrustDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

final class DPTClient {
    private static let deviceDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private let trustDelegate = TrustDelegate()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        return URLSession(configuration: config, delegate: trustDelegate, delegateQueue: nil)
    }()

    private var credentials: String?
    private var pending: RegistrationContext?

    func checkConnection(host: String) async throws -> String {
        let result = try await request(host: host, secure: false, method: "GET", path: "/register/information")
        let info = try json(result.data)
        guard let model = info["model_name"] as? String,
              let serial = info["serial_number"] as? String else { throw DPTError.invalidResponse }
        return "已连接 \(model) · \(serial)"
    }

    func beginRegistration(host: String) async throws {
        _ = try? await request(host: host, secure: false, method: "PUT", path: "/register/cleanup")
        let m1 = try json(try await request(host: host, secure: false, method: "POST", path: "/register/pin").data)
        let n1 = try data(m1, "a")
        let mac = try data(m1, "b")
        let yb = try data(m1, "c")
        let n2 = try DPTCrypto.randomData(count: 16)
        let dh = try DPTCrypto.makeDH(devicePublic: yb)
        let keys = try DPTCrypto.deriveKey(sharedKey: dh.sharedKey, salt: n1 + mac + n2)
        let m2hmac = try DPTCrypto.hmac(key: keys.auth, data: n1 + mac + yb + n1 + n2 + mac + dh.publicKey)
        let m2 = encode(["a": n1, "b": n2, "c": mac, "d": dh.publicKey, "e": m2hmac])
        let m3 = try json(try await request(host: host, secure: false, method: "POST", path: "/register/hash", body: m2).data)
        guard try data(m3, "a") == n2 else { throw DPTError.crypto }
        let eHash = try data(m3, "b")
        let m3hmac = try data(m3, "e")
        let expected = try DPTCrypto.hmac(key: keys.auth, data: n1 + n2 + mac + dh.publicKey + m2hmac + n2 + eHash)
        guard expected == m3hmac else { throw DPTError.crypto }
        pending = RegistrationContext(
            host: host, n1: n1, n2: n2, yb: yb, ya: dh.publicKey,
            eHash: eHash, m3hmac: m3hmac, authKey: keys.auth, wrapKey: keys.wrap
        )
    }

    func finishRegistration(pin: String) async throws -> String {
        guard let context = pending else { throw DPTError.crypto }
        let psk = try DPTCrypto.hmac(key: context.authKey, data: Data(pin.utf8))
        let rs = try DPTCrypto.randomData(count: 16)
        let rHash = try DPTCrypto.hmac(key: context.authKey, data: rs + psk + context.yb + context.ya)
        let wrappedRS = try DPTCrypto.wrap(rs, authKey: context.authKey, wrapKey: context.wrapKey)
        let m4hmac = try DPTCrypto.hmac(
            key: context.authKey,
            data: context.n2 + context.eHash + context.m3hmac + context.n1 + rHash + wrappedRS
        )
        let m4 = encode(["a": context.n1, "b": rHash, "d": wrappedRS, "e": m4hmac])
        let m5 = try json(try await request(host: context.host, secure: false, method: "POST", path: "/register/ca", body: m4).data)
        guard try data(m5, "a") == context.n2 else { throw DPTError.crypto }
        let wrappedCertificate = try data(m5, "d")
        let m5hmac = try data(m5, "e")
        let expected = try DPTCrypto.hmac(
            key: context.authKey,
            data: context.n1 + rHash + wrappedRS + m4hmac + context.n2 + wrappedCertificate
        )
        guard expected == m5hmac else { throw DPTError.crypto }
        let certificate = try DPTCrypto.unwrap(wrappedCertificate, authKey: context.authKey, wrapKey: context.wrapKey)
        guard certificate.count > 16 else { throw DPTError.crypto }
        let es = Data(certificate.prefix(16))
        guard try DPTCrypto.hmac(key: context.authKey, data: es + psk + context.yb + context.ya) == context.eHash else {
            throw DPTError.crypto
        }

        let publicKey = try DPTCrypto.replaceRSAKey()
        let clientID = UUID().uuidString.lowercased()
        let wrappedIdentity = try DPTCrypto.wrap(
            Data(clientID.utf8) + Data(publicKey.utf8),
            authKey: context.authKey,
            wrapKey: context.wrapKey
        )
        let m6hmac = try DPTCrypto.hmac(
            key: context.authKey,
            data: context.n2 + wrappedCertificate + m5hmac + context.n1 + wrappedIdentity
        )
        let m6 = encode(["a": context.n1, "d": wrappedIdentity, "e": m6hmac])
        _ = try await request(host: context.host, secure: false, method: "POST", path: "/register", body: m6)
        _ = try? await request(host: context.host, secure: false, method: "PUT", path: "/register/cleanup")
        pending = nil
        return clientID
    }

    func authenticate(host: String, clientID: String) async throws {
        let nonceResponse = try json(try await request(
            host: host,
            secure: true,
            method: "GET",
            path: "/auth/nonce/\(clientID)"
        ).data)
        guard let nonce = nonceResponse["nonce"] as? String else { throw DPTError.invalidResponse }
        let signature = try DPTCrypto.sign(Data(nonce.utf8)).base64EncodedString()
        let response = try await request(
            host: host,
            secure: true,
            method: "PUT",
            path: "/auth",
            jsonBody: ["client_id": clientID, "nonce_signed": signature]
        )
        guard let cookie = response.response.value(forHTTPHeaderField: "Set-Cookie")?.split(separator: ";").first else {
            throw DPTError.invalidResponse
        }
        credentials = String(cookie)
    }

    func documents(host: String, clientID: String) async throws -> [DPTDocument] {
        try await ensureAuthenticated(host: host, clientID: clientID)
        let payload = try json(try await authorized(host: host, method: "GET", path: "/documents2?entry_type=all").data)
        guard let entries = payload["entry_list"] as? [[String: Any]] else { throw DPTError.invalidResponse }
        return entries.compactMap { entry in
            guard entry["entry_type"] as? String == "document",
                  let id = entry["entry_id"] as? String,
                  let path = entry["entry_path"] as? String else { return nil }
            return DPTDocument(
                id: id,
                path: path,
                currentPage: Int(entry["current_page"] as? String ?? "1") ?? 1,
                totalPages: Int(entry["total_page"] as? String ?? "1") ?? 1,
                modifiedDate: (entry["modified_date"] as? String).flatMap(Self.deviceDateFormatter.date)
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func refresh(documentPath: String, host: String, clientID: String) async throws -> DPTDocument {
        try await ensureAuthenticated(host: host, clientID: clientID)
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = documentPath.addingPercentEncoding(withAllowedCharacters: allowed) ?? documentPath
        let entry = try json(try await authorized(host: host, method: "GET", path: "/resolve/entry/path/\(encoded)").data)
        guard let id = entry["entry_id"] as? String,
              let path = entry["entry_path"] as? String else { throw DPTError.invalidResponse }
        return DPTDocument(
            id: id,
            path: path,
            currentPage: Int(entry["current_page"] as? String ?? "1") ?? 1,
            totalPages: Int(entry["total_page"] as? String ?? "1") ?? 1,
            modifiedDate: (entry["modified_date"] as? String).flatMap(Self.deviceDateFormatter.date)
        )
    }

    func open(documentID: String, page: Int, host: String, clientID: String) async throws {
        try await ensureAuthenticated(host: host, clientID: clientID)
        _ = try await authorized(
            host: host,
            method: "PUT",
            path: "/viewer/controls/open2",
            jsonBody: ["document_id": documentID, "page": page]
        )
    }

    private func ensureAuthenticated(host: String, clientID: String) async throws {
        if credentials == nil { try await authenticate(host: host, clientID: clientID) }
    }

    private func authorized(host: String, method: String, path: String, jsonBody: [String: Any]? = nil) async throws -> HTTPResult {
        do {
            return try await request(host: host, secure: true, method: method, path: path, jsonBody: jsonBody, cookie: credentials)
        } catch {
            credentials = nil
            guard let clientID = UserDefaults.standard.string(forKey: "dptClientID") else {
                throw error
            }
            try await authenticate(host: host, clientID: clientID)
            return try await request(
                host: host,
                secure: true,
                method: method,
                path: path,
                jsonBody: jsonBody,
                cookie: credentials
            )
        }
    }

    private func request(
        host: String,
        secure: Bool,
        method: String,
        path: String,
        body: Data? = nil,
        jsonBody: [String: Any]? = nil,
        cookie: String? = nil
    ) async throws -> HTTPResult {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty else { throw DPTError.invalidAddress }
        let scheme = secure ? "https" : "http"
        let port = secure ? 8443 : 8080
        guard let url = URL(string: "\(scheme)://\(cleanHost):\(port)\(path)") else { throw DPTError.invalidAddress }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = try jsonBody.map { try JSONSerialization.data(withJSONObject: $0) } ?? body
        if request.httpBody != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let cookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        let dataAndResponse: (Data, URLResponse)
        do {
            dataAndResponse = try await session.data(for: request)
        } catch {
            throw mapNetworkError(error)
        }
        let (data, response) = dataAndResponse
        guard let http = response as? HTTPURLResponse else { throw DPTError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            let message = (try? json(data)["message"] as? String) ?? "DPT 请求失败（\(http.statusCode)）"
            throw DPTError.request(message)
        }
        return HTTPResult(data: data, response: http)
    }

    private func mapNetworkError(_ error: Error) -> Error {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return DPTError.request("Watch 没有可用网络，请确认它已连接 Up Wi-Fi")
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorTimedOut:
                return DPTError.request("无法连接 DPT，请确认地址为 192.168.31.227 且在同一 Wi-Fi")
            default: break
            }
        }
        return error
    }

    private func json(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DPTError.invalidResponse
        }
        return value
    }

    private func data(_ json: [String: Any], _ key: String) throws -> Data {
        guard let value = json[key] as? String, let data = Data(base64Encoded: value) else {
            throw DPTError.invalidResponse
        }
        return data
    }

    private func encode(_ values: [String: Data]) -> Data {
        try! JSONSerialization.data(withJSONObject: values.mapValues { $0.base64EncodedString() })
    }
}

private struct HTTPResult {
    let data: Data
    let response: HTTPURLResponse
}

private struct RegistrationContext {
    let host: String
    let n1: Data
    let n2: Data
    let yb: Data
    let ya: Data
    let eHash: Data
    let m3hmac: Data
    let authKey: [UInt8]
    let wrapKey: [UInt8]
}
