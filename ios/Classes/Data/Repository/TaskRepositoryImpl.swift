import Foundation

/// Реализация репозитория для работы с задачами HTTP запросов
///
/// Использует TaskQueueManager для управления очередью задач,
/// что позволяет избежать зависания при регистрации большого числа задач.
actor TaskRepositoryImpl: TaskRepository {
    private let fileStorage: FileStorageDataSource
    private let urlSession: URLSessionDataSource
    private let queueManager: TaskQueueManager
    
    // Set для отслеживания запросов, которые находятся в процессе создания
    private var creatingTasks = Set<String>()
    
    init() {
        self.fileStorage = FileStorageDataSource()
        self.urlSession = URLSessionDataSource()
        self.queueManager = TaskQueueManager.shared
        
        // Устанавливаем callback для выполнения задач из очереди
        Task {
            await queueManager.setExecuteCallback { [weak self] requestId in
                await self?.executeQueuedTask(requestId: requestId)
            }
            
            // Обрабатываем восстановленную очередь
            await queueManager.processQueue()
        }
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
            // Проверяем, находится ли он в очереди или активен
            if await queueManager.isTaskPendingOrActive(requestId) {
                return existingTask
            }
            
            // Проверяем статус запроса
            let status = existingTask.status
            if status == .inProgress {
                // Запрос уже выполняется, добавляем в очередь
                _ = await queueManager.enqueue(requestId)
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
        
        // Добавляем задачу в очередь (вместо прямого запуска)
        // TaskQueueManager сам решит, когда запустить задачу
        _ = await queueManager.enqueue(requestId)
        
        return taskInfo
    }
    
    /// Выполняет задачу из очереди
    private func executeQueuedTask(requestId: String) async {
        guard let taskInfo = fileStorage.loadTaskInfo(requestId: requestId) else {
            print("[TaskRepositoryImpl] Task info not found for: \(requestId)")
            await queueManager.onTaskCompleted(requestId)
            return
        }
        
        // Загружаем данные запроса из файла
        guard let requestData = fileStorage.loadRequestData(requestId: requestId) else {
            print("[TaskRepositoryImpl] Request data not found for: \(requestId)")
            await queueManager.onTaskCompleted(requestId)
            return
        }
        
        guard let url = URL(string: requestData.url) else {
            print("[TaskRepositoryImpl] Invalid URL for: \(requestId)")
            await queueManager.onTaskCompleted(requestId)
            return
        }
        
        // Выполняем запрос
        do {
            try await urlSession.executeRequest(
                requestId: requestId,
                url: url,
                method: requestData.method,
                headers: requestData.headers,
                body: requestData.body,
                queryParameters: requestData.queryParameters,
                timeout: requestData.timeout ?? 120,
                multipartFields: requestData.multipartFields,
                multipartFiles: requestData.multipartFiles,
                retries: requestData.retries ?? 0,
                fileStorage: fileStorage,
                onCompleted: { [weak self] in
                    Task {
                        await self?.queueManager.onTaskCompleted(requestId)
                    }
                }
            )
        } catch {
            print("[TaskRepositoryImpl] Error executing request \(requestId): \(error)")
            await queueManager.onTaskCompleted(requestId)
        }
    }
    
    func getTaskInfo(requestId: String) async throws -> TaskInfo? {
        guard var taskInfo = fileStorage.loadTaskInfo(requestId: requestId) else {
            return nil
        }
        
        // Если статус IN_PROGRESS, проверяем актуальное состояние
        if taskInfo.status == .inProgress {
            // Проверяем наличие файла ответа
            if let responseTaskInfo = fileStorage.loadTaskResponse(requestId: requestId),
               let responseJson = responseTaskInfo.responseJson {
                // Файл ответа существует, значит запрос завершен
                if let statusValue = responseJson["status"] as? Int,
                   let status = RequestStatus(rawValue: statusValue),
                   status != .inProgress {
                    // Обновляем статус
                    try? fileStorage.saveStatus(requestId: requestId, status: status)
                    // Уведомляем очередь о завершении
                    await queueManager.onTaskCompleted(requestId)
                    taskInfo = TaskInfo(
                        id: taskInfo.id,
                        status: status,
                        path: taskInfo.path,
                        registrationDate: taskInfo.registrationDate,
                        responseJson: taskInfo.responseJson
                    )
                }
            } else {
                // Проверяем, находится ли задача в очереди (ещё не запущена)
                if await queueManager.isTaskQueued(requestId) {
                    // Задача в очереди, статус IN_PROGRESS корректен
                    return taskInfo
                }
                
                // Если задача не в очереди и не активна, возможно она потеряна
                if await !queueManager.isTaskPendingOrActive(requestId) {
                    // Добавляем обратно в очередь
                    _ = await queueManager.enqueue(requestId)
                }
            }
        }
        
        return taskInfo
    }
    
    func getTaskResponse(requestId: String) async throws -> TaskInfo? {
        let response = fileStorage.loadTaskResponse(requestId: requestId)
        
        // Если получили ответ, уведомляем очередь о завершении
        if response?.responseJson != nil {
            await queueManager.onTaskCompleted(requestId)
        }
        
        return response
    }
    
    func cancelTask(requestId: String) async throws -> Bool? {
        guard fileStorage.taskExists(requestId: requestId) else {
            return nil
        }
        
        do {
            // Удаляем из очереди, если задача там
            _ = await queueManager.removeFromQueue(requestId)
            // Отменяем в URLSession, если задача там
            urlSession.cancelTask(requestId: requestId)
            // Уведомляем очередь о завершении
            await queueManager.onTaskCompleted(requestId)
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
            // Удаляем из очереди
            _ = await queueManager.removeFromQueue(requestId)
            // Уведомляем очередь о завершении (на случай если задача была активна)
            await queueManager.onTaskCompleted(requestId)
            urlSession.deleteTask(requestId: requestId)
            let deleted = fileStorage.deleteTaskFiles(requestId: requestId)
            return deleted
        } catch {
            return false
        }
    }
    
    func getPendingTasks() async throws -> [PendingTask] {
        // Получаем все задачи из файловой системы
        let allTaskIds = fileStorage.getAllTaskIds()
        var pendingTasks: [PendingTask] = []
        
        for requestId in allTaskIds {
            // Проверяем, что задача в ожидании или выполняется
            if let taskInfo = try await getTaskInfo(requestId: requestId),
               taskInfo.status == .inProgress {
                // Проверяем, что нет ответа (задача еще не завершена)
                if let responseInfo = fileStorage.loadTaskResponse(requestId: requestId),
                   responseInfo.responseJson == nil {
                    pendingTasks.append(PendingTask(
                        requestId: requestId,
                        registrationDate: taskInfo.registrationDate
                    ))
                } else if fileStorage.loadTaskResponse(requestId: requestId) == nil {
                    pendingTasks.append(PendingTask(
                        requestId: requestId,
                        registrationDate: taskInfo.registrationDate
                    ))
                }
            }
        }
        
        return pendingTasks
    }
    
    func cancelAllTasks() async throws -> Int {
        // Очищаем нашу очередь
        let queueCleared = await queueManager.clearAll()
        // Отменяем активные задачи в URLSession
        _ = urlSession.cancelAllTasks()
        return queueCleared
    }
    
    // MARK: - Queue Management Methods
    
    /// Получает статистику очереди
    func getQueueStats() async -> QueueStats {
        return await queueManager.getQueueStats()
    }
    
    /// Устанавливает максимальное количество одновременных задач
    func setMaxConcurrentTasks(_ count: Int) async {
        await queueManager.setMaxConcurrentTasks(count)
    }
    
    /// Устанавливает максимальный размер очереди
    func setMaxQueueSize(_ size: Int) async {
        await queueManager.setMaxQueueSize(size)
    }
    
    /// Принудительно обрабатывает очередь
    func processQueue() async {
        await queueManager.processQueue()
    }
}
