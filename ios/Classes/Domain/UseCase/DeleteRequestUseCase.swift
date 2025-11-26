import Foundation

/// Use case для удаления задачи
struct DeleteRequestUseCase {
    private let repository: TaskRepository
    
    init(repository: TaskRepository) {
        self.repository = repository
    }
    
    func execute(requestId: String) async throws -> Bool? {
        return try await repository.deleteTask(requestId: requestId)
    }
}

