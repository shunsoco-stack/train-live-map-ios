import Foundation

enum APIClientError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case serverMessage(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "API URLを作成できませんでした"
        case .invalidResponse:
            "APIから不正な応答を受信しました"
        case let .httpStatus(statusCode):
            "APIがエラーを返しました（HTTP \(statusCode)）"
        case let .serverMessage(_, message):
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

    init(baseURL: URL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 12
            configuration.timeoutIntervalForResource = 20
            configuration.waitsForConnectivity = true
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
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
        try await fetch(
            path: "api/community-reports",
            method: "POST",
            body: try JSONEncoder.trainLiveMap.encode(vote),
            headers: [
                "Content-Type": "application/json",
                "x-community-reporter": reporterID
            ]
        )
    }

    private func fetch<Response: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String] = [:]
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
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
        guard (200..<300).contains(httpResponse.statusCode) else {
            if let payload = try? decoder.decode(APIErrorResponse.self, from: data),
               !payload.error.isEmpty {
                throw APIClientError.serverMessage(
                    statusCode: httpResponse.statusCode,
                    message: payload.error
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
