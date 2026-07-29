import Foundation

enum APIClientError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "API URLを作成できませんでした"
        case .invalidResponse:
            "APIから不正な応答を受信しました"
        case let .httpStatus(statusCode):
            "APIがエラーを返しました（HTTP \(statusCode)）"
        }
    }
}

protocol TrainAPIService: Sendable {
    func fetchTrains() async throws -> TrainsAPIResponse
    func fetchServiceStatus() async throws -> ServiceStatusAPIResponse
    func fetchRailways() async throws -> RailwaysAPIResponse
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

    private func fetch<Response: Decodable>(path: String) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw APIClientError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("TrainLiveMap-iOS/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIClientError.httpStatus(httpResponse.statusCode)
        }
        return try decoder.decode(Response.self, from: data)
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
