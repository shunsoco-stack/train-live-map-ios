import Foundation

struct NotificationPreferences: Codable, Equatable, Sendable {
    var enabled = false
    var includeCommunity = false
    var suspension = true
    var resumption = true
    var delay = false
}
