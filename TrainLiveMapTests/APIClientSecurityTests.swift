import XCTest
@testable import TrainLiveMap

final class APIClientSecurityTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testCommunityReportUsesJSONAndReporterHeader() async throws {
        let recorder = RequestRecorder()
        URLProtocolStub.handler = { request in
            recorder.record(request)
            return try Self.response(
                for: request,
                statusCode: 201,
                data: Self.submitResponseData()
            )
        }

        let service = makeService()
        let vote = CommunityReportVote(
            lineId: "JR-East.Tokaido",
            status: .delayed,
            delayMinutes: 8
        )
        _ = try await service.submitCommunityReport(
            vote,
            reporterID: "0123456789abcdef0123456789abcdef"
        )

        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Type"),
            "application/json"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-Community-Reporter"),
            "0123456789abcdef0123456789abcdef"
        )
        XCTAssertEqual(
            try JSONDecoder.trainLiveMap.decode(
                CommunityReportVote.self,
                from: try XCTUnwrap(request.httpBody)
            ),
            vote
        )
    }

    func testMapsCommunitySecurityStatusesIndividually() async throws {
        let cases: [(Int, String)] = [
            (403, "投稿元を確認できません。"),
            (413, "投稿データが大きすぎます。"),
            (415, "Content-Typeはapplication/jsonにしてください。")
        ]

        for (statusCode, message) in cases {
            URLProtocolStub.handler = { request in
                try Self.response(
                    for: request,
                    statusCode: statusCode,
                    data: try JSONEncoder().encode(["error": message])
                )
            }
            do {
                _ = try await makeService().submitCommunityReport(
                    Self.vote,
                    reporterID: Self.reporterID
                )
                XCTFail("HTTP \(statusCode) should fail")
            } catch let error as APIClientError {
                switch (statusCode, error) {
                case (403, .forbidden(let actual)),
                     (413, .payloadTooLarge(let actual)),
                     (415, .unsupportedMediaType(let actual)):
                    XCTAssertEqual(actual, message)
                default:
                    XCTFail("Unexpected mapping: \(error)")
                }
            }
        }
    }

    func testRetryAfterBlocksAnotherSubmissionUntilDeadline() async throws {
        let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
        let recorder = RequestRecorder()
        URLProtocolStub.handler = { request in
            recorder.record(request)
            return try Self.response(
                for: request,
                statusCode: 429,
                headers: ["Retry-After": "120"],
                data: try JSONEncoder().encode([
                    "error": "同じ路線には120秒後に再投票できます。"
                ])
            )
        }
        let service = makeService(now: { fixedNow })

        for attempt in 1...2 {
            do {
                _ = try await service.submitCommunityReport(
                    Self.vote,
                    reporterID: Self.reporterID
                )
                XCTFail("Attempt \(attempt) should be rate limited")
            } catch let APIClientError.rateLimited(retryAfter, message) {
                XCTAssertEqual(
                    retryAfter,
                    fixedNow.addingTimeInterval(120)
                )
                XCTAssertEqual(
                    message,
                    "同じ路線には120秒後に再投票できます。"
                )
            }
        }

        XCTAssertEqual(recorder.requests.count, 1)
    }

    func testRetryAfterParsesHTTPDate() throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let expected = try XCTUnwrap(
            formatter.date(from: "Sat, 01 Aug 2026 07:00:00 GMT")
        )

        XCTAssertEqual(
            RetryAfterParser.date(
                from: "Sat, 01 Aug 2026 07:00:00 GMT",
                now: .distantPast
            ),
            expected
        )
    }

    private func makeService(
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> URLSessionTrainAPIService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSessionTrainAPIService(
            baseURL: URL(string: "https://example.com")!,
            session: URLSession(configuration: configuration),
            now: now
        )
    }

    private static let reporterID = "0123456789abcdef0123456789abcdef"
    private static let vote = CommunityReportVote(
        lineId: "JR-East.Tokaido",
        status: .onTime,
        delayMinutes: nil
    )

    private static func response(
        for request: URLRequest,
        statusCode: Int,
        headers: [String: String] = [:],
        data: Data
    ) throws -> (HTTPURLResponse, Data) {
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: headers
            )
        )
        return (response, data)
    }

    private static func submitResponseData() throws -> Data {
        let summary = CommunityReportSummary(
            lineId: "JR-East.Tokaido",
            status: .delayed,
            delayMinutes: 8,
            voteCount: 1,
            counts: CommunityReportCounts(
                onTime: 0,
                delayed: 1,
                suspended: 0
            ),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        return try JSONEncoder.trainLiveMap.encode(
            CommunityReportSubmitResponse(
                summaries: [summary],
                windowMinutes: 30,
                cooldownSeconds: 60,
                persistent: true,
                votingEnabled: true,
                summary: summary
            )
        )
    }
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URLRequest] = []

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ request: URLRequest) {
        var capturedRequest = request
        capturedRequest.httpBody = TestRequestBody.data(from: request)
        lock.lock()
        storage.append(capturedRequest)
        lock.unlock()
    }
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws ->
        (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(
                self,
                didFailWithError: APIClientError.invalidResponse
            )
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
