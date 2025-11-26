import Foundation

/// Use case для создания HTTP запроса
struct CreateRequestUseCase {
    private let repository: TaskRepository
    
    init(repository: TaskRepository) {
        self.repository = repository
    }
    
    func execute(request: HttpRequest) async throws -> TaskInfo {
        return try await repository.createTask(request: request)
    }
}

