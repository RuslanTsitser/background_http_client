import Foundation

/// Repository for working with HTTP request tasks
protocol TaskRepository {
    /// Creates a new HTTP request task
    func createTask(request: HttpRequest) async throws -> TaskInfo
    
    /// Gets task information by ID
    func getTaskInfo(requestId: String) async throws -> TaskInfo?
    
    /// Gets task response by ID
    func getTaskResponse(requestId: String) async throws -> TaskInfo?
    
    /// Cancels a task by ID
    func cancelTask(requestId: String) async throws -> Bool?
    
    /// Deletes a task and all related files by ID
    func deleteTask(requestId: String) async throws -> Bool?
    
    /// Gets a list of pending tasks with registration dates
    func getPendingTasks() async throws -> [PendingTask]
    
    /// Cancels all tasks
    /// Returns the number of cancelled tasks
    func cancelAllTasks() async throws -> Int
}

/// Information about a pending task
struct PendingTask {
    let requestId: String
    let registrationDate: Int64
}

