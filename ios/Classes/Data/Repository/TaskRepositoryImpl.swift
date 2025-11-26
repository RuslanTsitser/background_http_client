import Foundation

/// Реализация репозитория для работы с задачами HTTP запросов
class TaskRepositoryImpl: TaskRepository {
    private let fileStorage: FileStorageDataSource
    private let urlSession: URLSessionDataSource
    
    init() {
        self.fileStorage = FileStorageDataSource()
        self.urlSession = URLSessionDataSource()
    }
    
    func createTask(request: HttpRequest) async throws -> TaskInfo {
        let requestId = request.requestId ?? RequestMapper.generateRequestId()
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

