import Foundation

/// Информация о задаче в нативном HTTP сервисе
struct TaskInfo {
    let id: String
    let status: RequestStatus
    let path: String
    let registrationDate: Int64 // timestamp в миллисекундах
    let responseJson: [String: Any]?
}

