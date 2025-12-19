import Foundation

/// Information about a task in the native HTTP service
struct TaskInfo {
    let id: String
    let status: RequestStatus
    let path: String
    let registrationDate: Int64 // timestamp in milliseconds
    let responseJson: [String: Any]?
}

