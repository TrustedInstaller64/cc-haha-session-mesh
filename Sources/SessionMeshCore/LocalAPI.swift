import Foundation

enum LocalAPIError: LocalizedError, Equatable {
    case portFileMissing
    case invalidPort
    case requestFailed(String)
    case invalidResponse
    case badStatus(Int)
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .portFileMissing:
            return "desktop-server-state.json 不存在"
        case .invalidPort:
            return "无法解析 lastPort"
        case .requestFailed(let reason):
            return "本地 API 请求失败：\(reason)"
        case .invalidResponse:
            return "本地 API 响应无效"
        case .badStatus(let status):
            return "本地 API 返回状态 \(status)"
        case .decodeFailed(let reason):
            return "本地 API 响应解析失败：\(reason)"
        }
    }
}

struct SessionPage {
    let sessions: [Session]
    let total: Int
}

enum LocalAPI {
    static let requestLimit = 100
    static let maxPages = 100
    static let requestTimeout: TimeInterval = 5

    static func fetchSessions() throws -> [Session] {
        let port = try readPort()
        return try collectPages { offset in
            try requestPage(offset: offset, port: port)
        }
    }

    static func collectPages(fetch: (Int) throws -> SessionPage) throws -> [Session] {
        var result: [Session] = []
        var seen = Set<String>()
        var consumed = 0
        var pages = 0
        while pages < maxPages {
            let page = try fetch(consumed)
            guard !page.sessions.isEmpty else {
                break
            }
            let before = result.count
            for session in page.sessions where seen.insert(session.id).inserted {
                result.append(session)
            }
            // offset 必须跟随 API 已消费的条目数；用去重后数量会让偏移停滞
            consumed += page.sessions.count
            pages += 1
            if consumed >= page.total {
                break
            }
            if result.count == before {
                break
            }
        }
        return result
    }

    static func port(from stateData: Data) throws -> Int {
        struct ServerState: Decodable {
            let lastPort: Int
        }
        guard let state = try? JSONDecoder().decode(ServerState.self, from: stateData) else {
            throw LocalAPIError.invalidPort
        }
        return state.lastPort
    }

    static func readPort() throws -> Int {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/desktop-server-state.json")
        guard let data = try? Data(contentsOf: url) else {
            throw LocalAPIError.portFileMissing
        }
        return try port(from: data)
    }

    // MARK: - HTTP

    private static func requestPage(offset: Int, port: Int) throws -> SessionPage {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = port
        components.path = "/api/sessions"
        components.queryItems = [
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "limit", value: String(requestLimit))
        ]
        guard let url = components.url else {
            throw LocalAPIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeout
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try performSynchronously(request)
        } catch {
            throw LocalAPIError.requestFailed(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw LocalAPIError.badStatus(status)
        }
        return try decodePage(from: data)
    }

    static func decodePage(from data: Data) throws -> SessionPage {
        do {
            let page = try decoder().decode(PageDTO.self, from: data)
            return SessionPage(sessions: page.sessions.map(\.session), total: page.total)
        } catch {
            throw LocalAPIError.decodeFailed(error.localizedDescription)
        }
    }

    private static func performSynchronously(_ request: URLRequest) throws -> (Data, URLResponse) {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var result: Result<(Data, URLResponse), Error>?
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            let outcome: Result<(Data, URLResponse), Error>
            if let error {
                outcome = .failure(error)
            } else if let data, let response {
                outcome = .success((data, response))
            } else {
                outcome = .failure(LocalAPIError.invalidResponse)
            }
            lock.lock()
            result = outcome
            lock.unlock()
            semaphore.signal()
        }
        task.resume()
        guard semaphore.wait(timeout: .now() + requestTimeout + 5) == .success else {
            task.cancel()
            throw LocalAPIError.requestFailed("timeout")
        }
        lock.lock()
        let captured = result
        lock.unlock()
        guard let captured else {
            throw LocalAPIError.invalidResponse
        }
        return try captured.get()
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: text) {
                return date
            }
            guard let date = ISO8601DateFormatter().date(from: text) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "invalid date \(text)"
                )
            }
            return date
        }
        return decoder
    }

    // MARK: - Wire format

    private struct PageDTO: Decodable {
        let sessions: [SessionDTO]
        let total: Int
    }

    private struct SessionDTO: Decodable {
        let id: String
        let title: String?
        let createdAt: Date?
        let modifiedAt: Date?
        let projectRoot: String?
        let workDir: String?

        var session: Session {
            Session(
                id: id,
                title: title ?? "",
                state: .unknown,
                lastSeen: modifiedAt ?? createdAt ?? Date(),
                projectRoot: projectRoot,
                workDir: workDir,
                parentSessionId: nil,
                rootSessionId: nil
            )
        }
    }
}
