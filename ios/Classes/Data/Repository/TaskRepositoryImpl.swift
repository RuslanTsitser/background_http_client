import Foundation

/// Реализация репозитория для работы с задачами HTTP запросов
actor TaskRepositoryImpl: TaskRepository {
    private let fileStorage: FileStorageDataSource
    private let urlSession: URLSessionDataSource
    // Set для отслеживания запросов, которые находятся в процессе создания
    private var creatingTasks = Set<String>()
    
    init() {
        self.fileStorage = FileStorageDataSource()
        self.urlSession = URLSessionDataSource()
    }
    
    func createTask(request: HttpRequest) async throws -> TaskInfo {
        let requestId = request.requestId ?? RequestMapper.generateRequestId()
        
        // Защита от race condition: используем actor для синхронизации
        // Проверяем, не создается ли уже запрос с таким requestId
        if creatingTasks.contains(requestId) {
            // Запрос уже создается в другом потоке, ждем и возвращаем существующий
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            if let existingTask = try await getTaskInfo(requestId: requestId) {
                return existingTask
            }
            throw NSError(domain: "TaskRepositoryImpl", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to get task info after creation attempt"])
        }
        
        // Проверяем, существует ли уже запрос с таким requestId
        if let existingTask = try await getTaskInfo(requestId: requestId) {
            // Запрос уже существует
            // Проверяем статус запроса
            let status = existingTask.status
            if status == .inProgress {
                // Запрос уже выполняется, возвращаем существующий
                return existingTask
            } else if status == .completed || status == .failed {
                // Запрос уже завершен, возвращаем существующий
                return existingTask
            }
        }
        
        // Помечаем, что запрос создается
        creatingTasks.insert(requestId)
        
        defer {
            // Убираем из множества создающихся запросов
            creatingTasks.remove(requestId)
        }
        
        let registrationDate = Int64(Date().timeIntervalSince1970 * 1000)
        
        // Сохраняем запрос в файл
        let taskInfo = try fileStorage.saveRequest(request: request, requestId: requestId, registrationDate: registrationDate)
        
        // Запускаем запрос асинхронно
        guard let url = URL(string: request.url) else {
            throw NSError(domain: "TaskRepositoryImpl", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        Task {
            try? await urlSession.executeRequest(
                requestId: requestId,
                url: url,
                method: request.method,
                headers: request.headers,
                body: request.body,
                queryParameters: request.queryParameters,
                timeout: request.timeout ?? 120,
                multipartFields: request.multipartFields,
                multipartFiles: request.multipartFiles,
                retries: request.retries ?? 0,
                fileStorage: fileStorage
            )
        }
        
        return taskInfo
    }
    
    func getTaskInfo(requestId: String) async throws -> TaskInfo? {
        return fileStorage.loadTaskInfo(requestId: requestId)
    }
    
    func getTaskResponse(requestId: String) async throws -> TaskInfo? {
        return fileStorage.loadTaskResponse(requestId: requestId)
    }
    
    func cancelTask(requestId: String) async throws -> Bool? {
        guard fileStorage.taskExists(requestId: requestId) else {
            return nil
        }
        
        do {
            urlSession.cancelTask(requestId: requestId)
            try fileStorage.saveStatus(requestId: requestId, status: .failed)
            return true
        } catch {
            return false
        }
    }
    
    func deleteTask(requestId: String) async throws -> Bool? {
        guard fileStorage.taskExists(requestId: requestId) else {
            return nil
        }
        
        do {
            urlSession.deleteTask(requestId: requestId)
            let deleted = fileStorage.deleteTaskFiles(requestId: requestId)
            return deleted
        } catch {
            return false
        }
    }
}

