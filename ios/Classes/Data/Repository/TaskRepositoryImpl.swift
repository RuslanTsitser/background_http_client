import Foundation

/// Repository implementation for working with HTTP request tasks.
///
/// Uses TaskQueueManager to manage the task queue,
/// which helps avoid hangs when registering a large number of tasks.
actor TaskRepositoryImpl: TaskRepository {
    private let fileStorage: FileStorageDataSource
    private let urlSession: URLSessionDataSource
    private let queueManager: TaskQueueManager
    
    // Set to track requests that are currently being created
    private var creatingTasks = Set<String>()
    
    init() {
        self.fileStorage = FileStorageDataSource()
        self.urlSession = URLSessionDataSource()
        self.queueManager = TaskQueueManager.shared
        
        // Set callback for executing tasks from the queue
        Task {
            await queueManager.setExecuteCallback { [weak self] requestId in
                await self?.executeQueuedTask(requestId: requestId)
            }
            
            // Process restored queue
            await queueManager.processQueue()
        }
    }
    
    func createTask(request: HttpRequest) async throws -> TaskInfo {
        let requestId = request.requestId ?? RequestMapper.generateRequestId()
        
        // Race-condition protection: use the actor for synchronization
        // Check whether a request with such requestId is already being created
        if creatingTasks.contains(requestId) {
            // Request is already being created in another context; wait and return the existing one
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            if let existingTask = try await getTaskInfo(requestId: requestId) {
                return existingTask
            }
            throw NSError(domain: "TaskRepositoryImpl", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to get task info after creation attempt"])
        }
        
        // Check whether a request with such requestId already exists
        if let existingTask = try await getTaskInfo(requestId: requestId) {
            // Request already exists
            // Check whether it is in the queue or active
            if await queueManager.isTaskPendingOrActive(requestId) {
                return existingTask
            }
            
            // Check request status
            let status = existingTask.status
            if status == .inProgress {
                // Request is already executing; enqueue it
                _ = await queueManager.enqueue(requestId)
                return existingTask
            } else if status == .completed || status == .failed {
                // Request is already finished; return existing
                return existingTask
            }
        }
        
        // Mark that the request is being created
        creatingTasks.insert(requestId)
        
        defer {
            // Remove from the set of requests being created
            creatingTasks.remove(requestId)
        }
        
        let registrationDate = Int64(Date().timeIntervalSince1970 * 1000)
        
        // Save request to file
        let taskInfo = try fileStorage.saveRequest(request: request, requestId: requestId, registrationDate: registrationDate)
        
        // Add task to the queue (instead of starting it directly)
        // TaskQueueManager itself will decide when to start the task
        _ = await queueManager.enqueue(requestId)
        
        return taskInfo
    }
    
    /// Executes a task from the queue
    private func executeQueuedTask(requestId: String) async {
        guard let taskInfo = fileStorage.loadTaskInfo(requestId: requestId) else {
            print("[TaskRepositoryImpl] Task info not found for: \(requestId)")
            await queueManager.onTaskCompleted(requestId)
            return
        }
        
        // Load request data from file
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
        
        // Execute request
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
        
        // If status is IN_PROGRESS, check actual state
        if taskInfo.status == .inProgress {
            // Check if response file exists
            if let responseTaskInfo = fileStorage.loadTaskResponse(requestId: requestId),
               let responseJson = responseTaskInfo.responseJson {
                // Response file exists – request is completed
                if let statusValue = responseJson["status"] as? Int,
                   let status = RequestStatus(rawValue: statusValue),
                   status != .inProgress {
                    // Update status
                    try? fileStorage.saveStatus(requestId: requestId, status: status)
                    // Notify queue that the task is completed
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
                // Check whether the task is in the queue (not started yet)
                if await queueManager.isTaskQueued(requestId) {
                    // Task is in the queue; IN_PROGRESS status is correct
                    return taskInfo
                }
                
                // If the task is neither in the queue nor active, it might be lost
                if await !queueManager.isTaskPendingOrActive(requestId) {
                    // Add it back to the queue
                    _ = await queueManager.enqueue(requestId)
                }
            }
        }
        
        return taskInfo
    }
    
    func getTaskResponse(requestId: String) async throws -> TaskInfo? {
        let response = fileStorage.loadTaskResponse(requestId: requestId)
        
        // If we received a response, notify the queue that the task is completed
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
            // Remove from queue if the task is there
            _ = await queueManager.removeFromQueue(requestId)
            // Cancel in URLSession if the task is there
            urlSession.cancelTask(requestId: requestId)
            // Notify queue that the task is completed
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
            // Remove from queue
            _ = await queueManager.removeFromQueue(requestId)
            // Notify queue that the task is completed (in case it was active)
            await queueManager.onTaskCompleted(requestId)
            urlSession.deleteTask(requestId: requestId)
            let deleted = fileStorage.deleteTaskFiles(requestId: requestId)
            return deleted
        } catch {
            return false
        }
    }
    
    func getPendingTasks() async throws -> [PendingTask] {
        // Get all tasks from the file system
        let allTaskIds = fileStorage.getAllTaskIds()
        var pendingTasks: [PendingTask] = []
        
        for requestId in allTaskIds {
            // Check that the task is pending or running
            if let taskInfo = try await getTaskInfo(requestId: requestId),
               taskInfo.status == .inProgress {
                // Check that there is no response yet (task is not completed)
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
        // Clear our queue
        let queueCleared = await queueManager.clearAll()
        // Cancel active tasks in URLSession
        _ = urlSession.cancelAllTasks()
        return queueCleared
    }
    
    // MARK: - Queue Management Methods
    
    /// Gets queue statistics
    func getQueueStats() async -> QueueStats {
        return await queueManager.getQueueStats()
    }
    
    /// Sets the maximum number of concurrent tasks
    func setMaxConcurrentTasks(_ count: Int) async {
        await queueManager.setMaxConcurrentTasks(count)
    }
    
    /// Sets the maximum queue size
    func setMaxQueueSize(_ size: Int) async {
        await queueManager.setMaxQueueSize(size)
    }
    
    /// Forces queue processing
    func processQueue() async {
        await queueManager.processQueue()
    }
}
