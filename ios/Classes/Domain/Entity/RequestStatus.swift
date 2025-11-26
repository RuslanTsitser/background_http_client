import Foundation

/// Статусы выполнения HTTP запроса
enum RequestStatus: Int {
    case inProgress = 0
    case completed = 1
    case failed = 2
}

