import XCTest
@testable import TrainLiveMap

final class TrainAPIPhaseTests: XCTestCase {
    override func tearDown() {
        PhaseURLProtocolStub.handler = nil
        super.tearDown()
    }

    func testTrainAndServiceRequestsUseSortedSelectedLineQueryOnly() async throws {
        let recorder = PhaseRequestRecorder()
        let trainsData = try JSONEncoder.trainLiveMap.encode(
            TestFixture.trainsResponse
        )
        let serviceData = try JSONEncoder.trainLiveMap.encode(
            TestFixture.serviceResponse
        )
        PhaseURLProtocolStub.handler = { request in
            recorder.record(request)
            let data = request.url?.path == "/api/trains"
                ? trainsData
                : serviceData
            return try Self.response(for: request, statusCode: 200, data: data)
        }
        let service = makeService()
        let selected: Set<String> = ["yamanote", "tokaido"]

        _ = try await service.fetchTrains(lineIDs: selected)
        _ = try await service.fetchServiceStatus(lineIDs: selected)

        XCTAssertEqual(recorder.requests.count, 2)
        for request in recorder.requests {
            let components = try XCTUnwrap(
                URLComponents(
                    url: try XCTUnwrap(request.url),
                    resolvingAgainstBaseURL: false
                )
            )
            XCTAssertEqual(
                components.queryItems,
                [URLQueryItem(name: "lines", value: "tokaido,yamanote")]
            )
            XCTAssertNil(
                components.queryItems?.first { item in
                    ["latitude", "longitude", "lat", "lng"].contains(item.name)
                }
            )
        }
    }

    func testInvalidLineIDsAreRejectedBeforeNetworkRequest() async throws {
        let recorder = PhaseRequestRecorder()
        PhaseURLProtocolStub.handler = { request in
            recorder.record(request)
            return try Self.response(for: request, statusCode: 500, data: Data())
        }

        do {
            _ = try await makeService().fetchTrains(
                lineIDs: ["yamanote", "INVALID_LINE"]
            )
            XCTFail("Invalid line IDs must not be sent")
        } catch APIClientError.invalidLineIDs {
            // Expected.
        }
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    func testBadRequestBlocksSameRequestButAllowsChangedLines() async throws {
        let recorder = PhaseRequestRecorder()
        let successData = try JSONEncoder.trainLiveMap.encode(
            TestFixture.trainsResponse
        )
        PhaseURLProtocolStub.handler = { request in
            recorder.record(request)
            let lines = URLComponents(
                url: try XCTUnwrap(request.url),
                resolvingAgainstBaseURL: false
            )?.queryItems?.first { $0.name == "lines" }?.value
            if lines == "yamanote" {
                return try Self.response(
                    for: request,
                    statusCode: 400,
                    data: try JSONEncoder().encode([
                        "error": "路線指定を確認してください"
                    ])
                )
            }
            return try Self.response(
                for: request,
                statusCode: 200,
                data: successData
            )
        }
        let service = makeService()

        for _ in 0..<2 {
            do {
                _ = try await service.fetchTrains(lineIDs: ["yamanote"])
                XCTFail("The request should stay blocked")
            } catch let APIClientError.badRequest(message) {
                XCTAssertEqual(message, "路線指定を確認してください")
            }
        }
        _ = try await service.fetchTrains(lineIDs: ["tokaido"])
        do {
            _ = try await service.fetchTrains(lineIDs: ["yamanote"])
            XCTFail("The original selection should reach the server again")
        } catch APIClientError.badRequest {
            // The server still rejects it, but this is a fresh network check.
        }

        XCTAssertEqual(recorder.requests.count, 3)
    }

    func testRateLimitBlocksEndpointUntilRetryAfter() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let recorder = PhaseRequestRecorder()
        PhaseURLProtocolStub.handler = { request in
            recorder.record(request)
            return try Self.response(
                for: request,
                statusCode: 429,
                headers: ["Retry-After": "45"],
                data: try JSONEncoder().encode(["error": "待ってください"])
            )
        }
        let service = makeService(now: { now })

        for lines in [Set(["yamanote"]), Set(["tokaido"])] {
            do {
                _ = try await service.fetchTrains(lineIDs: lines)
                XCTFail("The endpoint should be rate limited")
            } catch let APIClientError.rateLimited(retryAfter, message) {
                XCTAssertEqual(retryAfter, now.addingTimeInterval(45))
                XCTAssertEqual(message, "待ってください")
            }
        }
        XCTAssertEqual(recorder.requests.count, 1)
    }

    func testServiceUnavailableWithoutRetryAfterWaitsAtLeastTenSeconds() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let recorder = PhaseRequestRecorder()
        PhaseURLProtocolStub.handler = { request in
            recorder.record(request)
            return try Self.response(
                for: request,
                statusCode: 503,
                data: try JSONEncoder().encode(["error": "準備中です"])
            )
        }
        let service = makeService(now: { now })

        for _ in 0..<2 {
            do {
                _ = try await service.fetchServiceStatus(lineIDs: ["yamanote"])
                XCTFail("The endpoint should stay unavailable")
            } catch let APIClientError.serviceUnavailable(
                retryAfter,
                message
            ) {
                XCTAssertEqual(retryAfter, now.addingTimeInterval(10))
                XCTAssertEqual(message, "準備中です")
            }
        }
        XCTAssertEqual(recorder.requests.count, 1)
    }

    func testReporterIDValidationIsAppliedImmediatelyBeforeSubmission() async throws {
        XCTAssertTrue(
            CommunityReporterIDValidator.isValid("Abcdefghij_-")
        )
        XCTAssertTrue(
            CommunityReporterIDValidator.isValid(
                String(repeating: "a", count: 100)
            )
        )
        XCTAssertFalse(
            CommunityReporterIDValidator.isValid(
                String(repeating: "a", count: 11)
            )
        )
        XCTAssertFalse(CommunityReporterIDValidator.isValid("invalid id 123"))
        XCTAssertFalse(
            CommunityReporterIDValidator.isValid(
                String(repeating: "a", count: 101)
            )
        )

        let recorder = PhaseRequestRecorder()
        PhaseURLProtocolStub.handler = { request in
            recorder.record(request)
            return try Self.response(for: request, statusCode: 500, data: Data())
        }
        do {
            _ = try await makeService().submitCommunityReport(
                CommunityReportVote(
                    lineId: "yamanote",
                    status: .onTime,
                    delayMinutes: nil
                ),
                reporterID: "invalid id"
            )
            XCTFail("Invalid reporter IDs must not be sent")
        } catch APIClientError.invalidReporterID {
            // Expected.
        }
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    private func makeService(
        now: @escaping @Sendable () -> Date = { .now }
    ) -> URLSessionTrainAPIService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PhaseURLProtocolStub.self]
        return URLSessionTrainAPIService(
            baseURL: URL(string: "https://example.com")!,
            session: URLSession(configuration: configuration),
            now: now
        )
    }

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
}

private final class PhaseRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URLRequest] = []

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ request: URLRequest) {
        lock.lock()
        storage.append(request)
        lock.unlock()
    }
}

private final class PhaseURLProtocolStub: URLProtocol, @unchecked Sendable {
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
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
