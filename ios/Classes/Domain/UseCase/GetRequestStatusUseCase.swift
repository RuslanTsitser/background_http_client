import Foundation

/// Use case for getting task status
struct GetRequestStatusUseCase {
    private let repository: TaskRepository
    
    init(repository: TaskRepository) {
        self.repository = repository
    }
    
    func execute(requestId: String) async throws -> TaskInfo? {
        return try await repository.getTaskInfo(requestId: requestId)
    }
}

