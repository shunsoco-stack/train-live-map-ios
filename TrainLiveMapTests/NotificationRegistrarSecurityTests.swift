import XCTest
@testable import TrainLiveMap

final class NotificationRegistrarSecurityTests: XCTestCase {
    override func tearDown() {
        APNSURLProtocolStub.handler = nil
        super.tearDown()
    }

    func testNativeRegistrarUsesPOSTAndDELETEContracts() async throws {
        let recorder = APNSRequestRecorder()
        APNSURLProtocolStub.handler = { request in
            recorder.record(request)
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 204,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [APNSURLProtocolStub.self]
        let endpoint = URL(string: "https://notify.example.com/api/apns/devices")!
        let registrar = try XCTUnwrap(
            APNSDeviceRegistrar(
                endpoint: endpoint,
                session: URLSession(configuration: configuration)
            )
        )

        try await registrar.register(
            deviceToken: String(repeating: "a", count: 64),
            lineIDs: ["yamanote"],
            installationSecret: String(repeating: "a", count: 64),
            preferences: NotificationPreferences(enabled: true)
        )
        try await registrar.unregister(deviceToken: String(repeating: "a", count: 64), installationSecret: String(repeating: "a", count: 64))

        let requests = recorder.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[1].httpMethod, "DELETE")
        XCTAssertEqual(
            requests[0].value(forHTTPHeaderField: "Content-Type"),
            "application/json"
        )

        let registerBody = try jsonBody(of: requests[0])
        XCTAssertEqual(registerBody["deviceToken"] as? String, String(repeating: "a", count: 64))
        XCTAssertEqual(registerBody["platform"] as? String, "ios")
        XCTAssertEqual(
            registerBody["bundleId"] as? String,
            "com.shunsoco.trainlivemap"
        )
        XCTAssertEqual(
            registerBody["lineIds"] as? [String],
            ["yamanote"]
        )

        let unregisterBody = try jsonBody(of: requests[1])
        XCTAssertEqual(unregisterBody["deviceToken"] as? String, String(repeating: "a", count: 64))
        XCTAssertEqual(unregisterBody["platform"] as? String, "ios")
        XCTAssertEqual(
            unregisterBody["bundleId"] as? String,
            "com.shunsoco.trainlivemap"
        )
        XCTAssertNil(unregisterBody["lineIds"])
        XCTAssertNil(unregisterBody["subscription"])
    }

    func testRegistrarRejectsWebPushAndHTTPURLs() {
        XCTAssertNil(
            APNSDeviceRegistrar(
                endpoint: URL(
                    string: "https://train-live-map.vercel.app/api/push/subscriptions"
                )!
            )
        )
        XCTAssertNil(
            APNSDeviceRegistrar(
                endpoint: URL(string: "http://notify.example.com/api/apns/devices")!
            )
        )
    }

    private func jsonBody(of request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: try XCTUnwrap(request.httpBody)
            ) as? [String: Any]
        )
    }
}

private final class APNSRequestRecorder: @unchecked Sendable {
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

private final class APNSURLProtocolStub: URLProtocol, @unchecked Sendable {
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
