import Foundation

/// Use case для получения ответа задачи
struct GetResponseUseCase {
    private let repository: TaskRepository
    
    init(repository: TaskRepository) {
        self.repository = repository
    }
    
    func execute(requestId: String) async throws -> TaskInfo? {
        return try await repository.getTaskResponse(requestId: requestId)
    }
}

