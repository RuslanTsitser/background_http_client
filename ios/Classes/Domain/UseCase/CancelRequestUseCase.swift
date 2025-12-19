import Foundation

/// Use case for canceling a task
struct CancelRequestUseCase {
    private let repository: TaskRepository
    
    init(repository: TaskRepository) {
        self.repository = repository
    }
    
    func execute(requestId: String) async throws -> Bool? {
        return try await repository.cancelTask(requestId: requestId)
    }
}

