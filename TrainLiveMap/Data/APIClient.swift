import Foundation

enum APIClientError: LocalizedError, Equatable, Sendable {
    case invalidURL
    case insecureURL
    case invalidResponse
    case httpStatus(Int)
    case serverMessage(statusCode: Int, message: String)
    case forbidden(message: String)
    case payloadTooLarge(message: String)
    case unsupportedMediaType(message: String)
    case rateLimited(retryAfter: Date, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "API URLを作成できませんでした"
        case .insecureURL:
            "HTTPSではないAPI URLへの通信は許可されていません"
        case .invalidResponse:
            "APIから不正な応答を受信しました"
        case let .httpStatus(statusCode):
            "APIがエラーを返しました（HTTP \(statusCode)）"
        case let .serverMessage(_, message):
            message
        case let .forbidden(message),
             let .payloadTooLarge(message),
             let .unsupportedMediaType(message),
             let .rateLimited(_, message):
            message
        }
    }
}

protocol TrainAPIService: Sendable {
    func fetchTrains() async throws -> TrainsAPIResponse
    func fetchServiceStatus() async throws -> ServiceStatusAPIResponse
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
    private let communityRetryGate = CommunityReportRetryGate()

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

    func fetchTrains() async throws -> TrainsAPIResponse {
        try await fetch(path: "api/trains")
    }

    func fetchServiceStatus() async throws -> ServiceStatusAPIResponse {
        try await fetch(path: "api/service-status")
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
        try await communityRetryGate.validate(now: now())
        do {
            let response: CommunityReportSubmitResponse = try await fetch(
                path: "api/community-reports",
                method: "POST",
                body: try JSONEncoder.trainLiveMap.encode(vote),
                headers: [
                    "Content-Type": "application/json",
                    "X-Community-Reporter": reporterID
                ]
            )
            return response
        } catch let error as APIClientError {
            if case let .rateLimited(retryAfter, message) = error {
                await communityRetryGate.block(
                    until: retryAfter,
                    message: message
                )
            }
            throw error
        }
    }

    private func fetch<Response: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String] = [:]
    ) async throws -> Response {
        let url = baseURL.appendingPathComponent(path)
        guard AppConfiguration.isSecureHTTPSURL(url) else {
            throw APIClientError.insecureURL
        }
        guard !path.isEmpty else {
            throw APIClientError.invalidURL
        }
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
            case 403:
                throw APIClientError.forbidden(
                    message: serverMessage?.isEmpty == false
                        ? serverMessage!
                        : "この投稿は受け付けられませんでした。"
                )
            case 413:
                throw APIClientError.payloadTooLarge(
                    message: serverMessage?.isEmpty == false
                        ? serverMessage!
                        : "投稿データが大きすぎます。"
                )
            case 415:
                throw APIClientError.unsupportedMediaType(
                    message: serverMessage?.isEmpty == false
                        ? serverMessage!
                        : "投稿はJSON形式で送信する必要があります。"
                )
            case 429:
                let retryAfter = RetryAfterParser.date(
                    from: httpResponse.value(
                        forHTTPHeaderField: "Retry-After"
                    ),
                    now: now()
                ) ?? now().addingTimeInterval(60)
                throw APIClientError.rateLimited(
                    retryAfter: retryAfter,
                    message: serverMessage?.isEmpty == false
                        ? serverMessage!
                        : "投稿が集中しています。しばらく待ってから再投稿してください。"
                )
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

private actor CommunityReportRetryGate {
    private var retryAfter: Date?
    private var message = ""

    func validate(now: Date) throws {
        guard let retryAfter else {
            return
        }
        guard retryAfter > now else {
            self.retryAfter = nil
            message = ""
            return
        }
        throw APIClientError.rateLimited(
            retryAfter: retryAfter,
            message: message
        )
    }

    func block(until retryAfter: Date, message: String) {
        self.retryAfter = retryAfter
        self.message = message
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
