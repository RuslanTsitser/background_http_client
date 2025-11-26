import Foundation

/// Репозиторий для работы с задачами HTTP запросов
protocol TaskRepository {
    /// Создает новую задачу HTTP запроса
    func createTask(request: HttpRequest) async throws -> TaskInfo
    
    /// Получает информацию о задаче по ID
    func getTaskInfo(requestId: String) async throws -> TaskInfo?
    
    /// Получает ответ задачи по ID
    func getTaskResponse(requestId: String) async throws -> TaskInfo?
    
    /// Отменяет задачу по ID
    func cancelTask(requestId: String) async throws -> Bool?
    
    /// Удаляет задачу и все связанные файлы по ID
    func deleteTask(requestId: String) async throws -> Bool?
    
    /// Получает список задач в ожидании с датами регистрации
    func getPendingTasks() async throws -> [PendingTask]
    
    /// Отменяет все задачи
    /// Возвращает количество отмененных задач
    func cancelAllTasks() async throws -> Int
}

/// Информация о задаче в ожидании
struct PendingTask {
    let requestId: String
    let registrationDate: Int64
}

