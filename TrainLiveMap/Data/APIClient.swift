import Foundation

enum APIClientError: LocalizedError, Equatable, Sendable {
    case invalidURL
    case invalidLineIDs
    case invalidReporterID
    case insecureURL
    case invalidResponse
    case httpStatus(Int)
    case serverMessage(statusCode: Int, message: String)
    case badRequest(message: String)
    case forbidden(message: String)
    case payloadTooLarge(message: String)
    case unsupportedMediaType(message: String)
    case rateLimited(retryAfter: Date, message: String)
    case serviceUnavailable(retryAfter: Date, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "API URLを作成できませんでした"
        case .invalidLineIDs:
            "路線指定を確認してください"
        case .invalidReporterID:
            "匿名端末IDを確認できないため投稿を送信しません"
        case .insecureURL:
            "HTTPSではないAPI URLへの通信は許可されていません"
        case .invalidResponse:
            "APIから不正な応答を受信しました"
        case let .httpStatus(statusCode):
            "APIがエラーを返しました（HTTP \(statusCode)）"
        case let .serverMessage(_, message):
            message
        case let .badRequest(message),
             let .forbidden(message),
             let .payloadTooLarge(message),
             let .unsupportedMediaType(message),
             let .rateLimited(_, message),
             let .serviceUnavailable(_, message):
            message
        }
    }
}

protocol TrainAPIService: Sendable {
    func fetchTrains(lineIDs: Set<String>) async throws -> TrainsAPIResponse
    func fetchServiceStatus(
        lineIDs: Set<String>
    ) async throws -> ServiceStatusAPIResponse
    func fetchRailways() async throws -> RailwaysAPIResponse
    func fetchCommunityReports() async throws -> CommunityReportsAPIResponse
    func submitCommunityReport(
        _ vote: CommunityReportVote,
        reporterID: String
    ) async throws -> CommunityReportSubmitResponse
}

final class URLSessionTrainAPIService: TrainAPIService, @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let now: @Sendable () -> Date
    private let responseRetryGate = HTTPResponseRetryGate()

    init(
        baseURL: URL,
        session: URLSession? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.baseURL = AppConfiguration.validatedAPIBaseURL(baseURL)
        self.now = now
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 12
            configuration.timeoutIntervalForResource = 20
            configuration.waitsForConnectivity = true
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(
                configuration: configuration,
                delegate: HTTPSOnlySessionDelegate(),
                delegateQueue: nil
            )
        }
        decoder = JSONDecoder.trainLiveMap
    }

    func fetchTrains(lineIDs: Set<String>) async throws -> TrainsAPIResponse {
        try await fetch(
            path: "api/trains",
            queryItems: try LineFilterQuery.queryItems(for: lineIDs)
        )
    }

    func fetchServiceStatus(
        lineIDs: Set<String>
    ) async throws -> ServiceStatusAPIResponse {
        try await fetch(
            path: "api/service-status",
            queryItems: try LineFilterQuery.queryItems(for: lineIDs)
        )
    }

    func fetchRailways() async throws -> RailwaysAPIResponse {
        try await fetch(path: "api/railways")
    }

    func fetchCommunityReports() async throws -> CommunityReportsAPIResponse {
        try await fetch(path: "api/community-reports")
    }

    func submitCommunityReport(
        _ vote: CommunityReportVote,
        reporterID: String
    ) async throws -> CommunityReportSubmitResponse {
        guard CommunityReporterIDValidator.isValid(reporterID) else {
            throw APIClientError.invalidReporterID
        }
        return try await fetch(
            path: "api/community-reports",
            method: "POST",
            body: try JSONEncoder.trainLiveMap.encode(vote),
            headers: [
                "Content-Type": "application/json",
                "X-Community-Reporter": reporterID
            ]
        )
    }

    private func fetch<Response: Decodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        headers: [String: String] = [:]
    ) async throws -> Response {
        guard !path.isEmpty else {
            throw APIClientError.invalidURL
        }
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else {
            throw APIClientError.invalidURL
        }
        guard AppConfiguration.isSecureHTTPSURL(url) else {
            throw APIClientError.insecureURL
        }
        let endpointKey = "\(method) \(path)"
        let requestKey = Self.requestKey(
            method: method,
            url: url,
            body: body
        )
        try await responseRetryGate.validate(
            endpointKey: endpointKey,
            requestKey: requestKey,
            now: now()
        )

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("TrainLiveMap-iOS/1.1", forHTTPHeaderField: "User-Agent")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        guard AppConfiguration.isSecureHTTPSURL(httpResponse.url) else {
            throw APIClientError.insecureURL
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let serverMessage = (try? decoder.decode(
                APIErrorResponse.self,
                from: data
            ))?.error.trimmingCharacters(in: .whitespacesAndNewlines)

            switch httpResponse.statusCode {
            case 400:
                let error = APIClientError.badRequest(
                    message: Self.message(
                        serverMessage,
                        fallback: "リクエスト内容を確認してください。"
                    )
                )
                await responseRetryGate.blockRequest(
                    endpointKey: endpointKey,
                    requestKey: requestKey,
                    with: error
                )
                throw error
            case 403:
                throw APIClientError.forbidden(
                    message: Self.message(
                        serverMessage,
                        fallback: "この投稿は受け付けられませんでした。"
                    )
                )
            case 413:
                throw APIClientError.payloadTooLarge(
                    message: Self.message(
                        serverMessage,
                        fallback: "投稿データが大きすぎます。"
                    )
                )
            case 415:
                throw APIClientError.unsupportedMediaType(
                    message: Self.message(
                        serverMessage,
                        fallback: "投稿はJSON形式で送信する必要があります。"
                    )
                )
            case 429:
                let retryAfter = retryDate(
                    from: httpResponse,
                    defaultInterval: 60
                )
                let error = APIClientError.rateLimited(
                    retryAfter: retryAfter,
                    message: Self.message(
                        serverMessage,
                        fallback: "アクセスが集中しています。しばらく待ってから再試行してください。"
                    )
                )
                await responseRetryGate.blockEndpoint(
                    endpointKey,
                    until: retryAfter,
                    with: error
                )
                throw error
            case 503:
                let retryAfter = retryDate(
                    from: httpResponse,
                    defaultInterval: 10
                )
                let error = APIClientError.serviceUnavailable(
                    retryAfter: retryAfter,
                    message: Self.message(
                        serverMessage,
                        fallback: "現在APIを利用できません。しばらく待ってから再試行してください。"
                    )
                )
                await responseRetryGate.blockEndpoint(
                    endpointKey,
                    until: retryAfter,
                    with: error
                )
                throw error
            default:
                break
            }

            if let serverMessage, !serverMessage.isEmpty {
                throw APIClientError.serverMessage(
                    statusCode: httpResponse.statusCode,
                    message: serverMessage
                )
            }
            throw APIClientError.httpStatus(httpResponse.statusCode)
        }
        return try decoder.decode(Response.self, from: data)
    }

    private func retryDate(
        from response: HTTPURLResponse,
        defaultInterval: TimeInterval
    ) -> Date {
        let currentDate = now()
        return RetryAfterParser.date(
            from: response.value(forHTTPHeaderField: "Retry-After"),
            now: currentDate
        ) ?? currentDate.addingTimeInterval(defaultInterval)
    }

    private static func message(
        _ serverMessage: String?,
        fallback: String
    ) -> String {
        guard let serverMessage, !serverMessage.isEmpty else {
            return fallback
        }
        return serverMessage
    }

    private static func requestKey(
        method: String,
        url: URL,
        body: Data?
    ) -> String {
        let encodedBody = body?.base64EncodedString() ?? ""
        return "\(method) \(url.absoluteString) \(encodedBody)"
    }
}

private struct APIErrorResponse: Decodable {
    let error: String
}

enum RetryAfterParser {
    static func date(from value: String?, now: Date) -> Date? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let seconds = TimeInterval(trimmed), seconds >= 0 {
            return now.addingTimeInterval(seconds)
        }

        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEEE, dd-MMM-yy HH:mm:ss zzz",
            "EEE MMM d HH:mm:ss yyyy"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }
}

enum LineFilterQuery {
    private static let lineIDPattern = #"^[a-z0-9-]{1,64}$"#
    private static let maximumLineCount = 44
    private static let maximumQueryLength = 1_024

    static func queryItems(for lineIDs: Set<String>) throws -> [URLQueryItem] {
        let sortedIDs = lineIDs.sorted()
        let value = sortedIDs.joined(separator: ",")
        guard sortedIDs.count <= maximumLineCount,
              value.count <= maximumQueryLength,
              sortedIDs.allSatisfy(isValidLineID) else {
            throw APIClientError.invalidLineIDs
        }
        return [URLQueryItem(name: "lines", value: value)]
    }

    private static func isValidLineID(_ value: String) -> Bool {
        value.range(of: lineIDPattern, options: .regularExpression) != nil
    }
}

enum CommunityReporterIDValidator {
    private static let pattern = #"^[A-Za-z0-9_-]{12,100}$"#

    static func isValid(_ value: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}

private actor HTTPResponseRetryGate {
    private struct RequestBlock {
        let requestKey: String
        let error: APIClientError
    }

    private struct TimedBlock {
        let retryAfter: Date
        let error: APIClientError
    }

    private var blockedRequests: [String: RequestBlock] = [:]
    private var blockedEndpoints: [String: TimedBlock] = [:]

    func validate(
        endpointKey: String,
        requestKey: String,
        now: Date
    ) throws {
        if let block = blockedRequests[endpointKey] {
            if block.requestKey == requestKey {
                throw block.error
            }
            // A changed selected-line query is an explicit correction. Clear
            // the previous 400 block so returning to that set later can be
            // checked against a refreshed server catalogue.
            blockedRequests.removeValue(forKey: endpointKey)
        }
        guard let block = blockedEndpoints[endpointKey] else {
            return
        }
        guard block.retryAfter > now else {
            blockedEndpoints.removeValue(forKey: endpointKey)
            return
        }
        throw block.error
    }

    func blockRequest(
        endpointKey: String,
        requestKey: String,
        with error: APIClientError
    ) {
        blockedRequests[endpointKey] = RequestBlock(
            requestKey: requestKey,
            error: error
        )
    }

    func blockEndpoint(
        _ endpointKey: String,
        until retryAfter: Date,
        with error: APIClientError
    ) {
        blockedEndpoints[endpointKey] = TimedBlock(
            retryAfter: retryAfter,
            error: error
        )
    }
}

extension JSONDecoder {
    static var trainLiveMap: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = ISO8601DateFormatter.fractional.date(from: value)
                ?? ISO8601DateFormatter.standard.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "ISO 8601日時を解析できません: \(value)"
            )
        }
        return decoder
    }
}

extension JSONEncoder {
    static var trainLiveMap: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension ISO8601DateFormatter {
    static let standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
