import Foundation

final class HTTPSOnlySessionDelegate: NSObject,
    URLSessionTaskDelegate,
    @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard AppConfiguration.isSecureHTTPSURL(request.url),
              request.url?.host?.lowercased()
                == task.originalRequest?.url?.host?.lowercased() else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
