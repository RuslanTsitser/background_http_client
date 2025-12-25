import Foundation

/// Task queue manager for controlling the number of concurrent requests.
///
/// Solves the problem of hanging when registering a large number of tasks in URLSession.
/// Instead of starting all tasks at once, TaskQueueManager keeps them in its own queue
/// and starts them in batches.
actor TaskQueueManager {
    
    // MARK: - Singleton
    
    static let shared = TaskQueueManager()
    
    // MARK: - Constants
    
    private let queueFileName = "pending_queue.json"
    private let defaultMaxConcurrentTasks = 30
    private let defaultMaxQueueSize = 10000
    
    // MARK: - Properties
    
    /// Queue of pending tasks (only requestId, data is on disk)
    private var pendingQueue: [String] = []
    
    /// Set of active tasks
    private var activeTasks: Set<String> = []
    
    /// Callback for starting a task (set by the repository)
    private var executeTaskCallback: ((String) async -> Void)?
    
    /// Maximum number of concurrent tasks
    private(set) var maxConcurrentTasks: Int
    
    /// Maximum queue size
    private(set) var maxQueueSize: Int
    
    // MARK: - Initialization
    
    private init() {
        self.maxConcurrentTasks = defaultMaxConcurrentTasks
        self.maxQueueSize = defaultMaxQueueSize
        
        // Restore queue on initialization (synchronously)
        if let restored = Self.loadQueueFromDisk() {
            self.pendingQueue = restored
            print("[TaskQueueManager] Restored \(restored.count) tasks from disk")
        }
    }
    
    // MARK: - Public Methods
    
    /// Sets callback for executing a task
    func setExecuteCallback(_ callback: @escaping (String) async -> Void) async {
        self.executeTaskCallback = callback
        print("[TaskQueueManager] Execute callback set, processing pending queue...")
        // Process any tasks that were enqueued before callback was set
        await processQueueInternal()
    }
    
    /// Adds a task to the queue.
    /// - Parameter requestId: task ID
    /// - Returns: true if the task was added, false if the queue is full
    func enqueue(_ requestId: String) async -> Bool {
        // Check queue size limit
        guard pendingQueue.count < maxQueueSize else {
            print("[TaskQueueManager] Queue is full (\(maxQueueSize)), rejecting task: \(requestId)")
            return false
        }
        
        // Check that this task has not already been added
        guard !pendingQueue.contains(requestId) && !activeTasks.contains(requestId) else {
            print("[TaskQueueManager] Task already in queue or active: \(requestId)")
            return true
        }
        
        pendingQueue.append(requestId)
        saveQueueToDisk()
        
        print("[TaskQueueManager] Task enqueued: \(requestId), queue size: \(pendingQueue.count), active: \(activeTasks.count)")
        
        // Try to start tasks
        await processQueueInternal()
        
        return true
    }
    
    /// Called when a task is completed (success or error)
    func onTaskCompleted(_ requestId: String) async {
        if activeTasks.remove(requestId) != nil {
            print("[TaskQueueManager] Task completed: \(requestId), active: \(activeTasks.count)")
            await processQueueInternal()
        }
    }
    
    /// Removes a task from the queue (if it has not been started yet)
    func removeFromQueue(_ requestId: String) -> Bool {
        if let index = pendingQueue.firstIndex(of: requestId) {
            pendingQueue.remove(at: index)
            saveQueueToDisk()
            print("[TaskQueueManager] Task removed from queue: \(requestId)")
            return true
        }
        return false
    }
    
    /// Checks whether a task is in the queue
    func isTaskQueued(_ requestId: String) -> Bool {
        return pendingQueue.contains(requestId)
    }
    
    /// Checks whether a task is active
    func isTaskActive(_ requestId: String) -> Bool {
        return activeTasks.contains(requestId)
    }
    
    /// Checks whether a task is pending or active
    func isTaskPendingOrActive(_ requestId: String) -> Bool {
        return isTaskQueued(requestId) || isTaskActive(requestId)
    }
    
    /// Returns queue statistics
    func getQueueStats() -> QueueStats {
        return QueueStats(
            pendingCount: pendingQueue.count,
            activeCount: activeTasks.count,
            maxConcurrent: maxConcurrentTasks,
            maxQueueSize: maxQueueSize
        )
    }
    
    /// Sets the maximum number of concurrent tasks
    func setMaxConcurrentTasks(_ count: Int) async {
        guard count >= 1 else {
            print("[TaskQueueManager] maxConcurrentTasks must be at least 1")
            return
        }
        maxConcurrentTasks = count
        
        // If the limit was increased, try to start additional tasks
        await processQueueInternal()
    }
    
    /// Sets the maximum queue size
    func setMaxQueueSize(_ size: Int) {
        guard size >= 1 else {
            print("[TaskQueueManager] maxQueueSize must be at least 1")
            return
        }
        maxQueueSize = size
    }
    
    /// Clears the entire queue
    func clearAll() -> Int {
        let totalCount = pendingQueue.count + activeTasks.count
        
        pendingQueue.removeAll()
        activeTasks.removeAll()
        saveQueueToDisk()
        
        print("[TaskQueueManager] Cleared all tasks: \(totalCount)")
        return totalCount
    }
    
    /// Forces queue processing
    func processQueue() async {
        await processQueueInternal()
    }
    
    // MARK: - Private Methods
    
    private func processQueueInternal() async {
        // Do not process the queue if callback is not set yet
        guard executeTaskCallback != nil else {
            print("[TaskQueueManager] Cannot process queue: executeTaskCallback is not set")
            return
        }
        
        while activeTasks.count < maxConcurrentTasks && !pendingQueue.isEmpty {
            let requestId = pendingQueue.removeFirst()
            activeTasks.insert(requestId)
            
            print("[TaskQueueManager] Started task: \(requestId), active: \(activeTasks.count), pending: \(pendingQueue.count)")
            
            // Start the task via callback
            if let callback = executeTaskCallback {
                Task {
                    await callback(requestId)
                }
            }
        }
        
        // Save queue after changes
        saveQueueToDisk()
    }
    
    // MARK: - Persistence
    
    private var queueFileURL: URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dirURL = documentsURL.appendingPathComponent("background_http_client", isDirectory: true)
        
        // Create directory if it does not exist
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        
        return dirURL.appendingPathComponent(queueFileName)
    }
    
    private func saveQueueToDisk() {
        do {
            let data = try JSONEncoder().encode(pendingQueue)
            try data.write(to: queueFileURL)
        } catch {
            print("[TaskQueueManager] Failed to save queue to disk: \(error)")
        }
    }
    
    private static func loadQueueFromDisk() -> [String]? {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL
            .appendingPathComponent("background_http_client", isDirectory: true)
            .appendingPathComponent("pending_queue.json")
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([String].self, from: data)
        } catch {
            print("[TaskQueueManager] Failed to load queue from disk: \(error)")
            return nil
        }
    }
}

// MARK: - Models

struct QueueStats {
    let pendingCount: Int
    let activeCount: Int
    let maxConcurrent: Int
    let maxQueueSize: Int
    
    func toDict() -> [String: Any] {
        return [
            "pendingCount": pendingCount,
            "activeCount": activeCount,
            "maxConcurrent": maxConcurrent,
            "maxQueueSize": maxQueueSize
        ]
    }
}

