import Foundation

/// Менеджер очереди задач для управления количеством одновременных запросов
///
/// Решает проблему зависания при регистрации большого числа задач в URLSession.
/// Вместо того чтобы сразу запускать все задачи, TaskQueueManager держит их в своей очереди
/// и запускает порциями.
actor TaskQueueManager {
    
    // MARK: - Singleton
    
    static let shared = TaskQueueManager()
    
    // MARK: - Constants
    
    private let queueFileName = "pending_queue.json"
    private let defaultMaxConcurrentTasks = 30
    private let defaultMaxQueueSize = 10000
    
    // MARK: - Properties
    
    /// Очередь ожидающих задач (только requestId, данные на диске)
    private var pendingQueue: [String] = []
    
    /// Множество активных задач
    private var activeTasks: Set<String> = []
    
    /// Callback для запуска задачи (будет установлен репозиторием)
    private var executeTaskCallback: ((String) async -> Void)?
    
    /// Максимальное количество одновременных задач
    private(set) var maxConcurrentTasks: Int
    
    /// Максимальный размер очереди
    private(set) var maxQueueSize: Int
    
    // MARK: - Initialization
    
    private init() {
        self.maxConcurrentTasks = defaultMaxConcurrentTasks
        self.maxQueueSize = defaultMaxQueueSize
        
        // Восстанавливаем очередь при инициализации (синхронно)
        if let restored = Self.loadQueueFromDisk() {
            self.pendingQueue = restored
            print("[TaskQueueManager] Restored \(restored.count) tasks from disk")
        }
    }
    
    // MARK: - Public Methods
    
    /// Устанавливает callback для выполнения задачи
    func setExecuteCallback(_ callback: @escaping (String) async -> Void) {
        self.executeTaskCallback = callback
    }
    
    /// Добавляет задачу в очередь
    /// - Parameter requestId: ID задачи
    /// - Returns: true если задача добавлена, false если очередь переполнена
    func enqueue(_ requestId: String) async -> Bool {
        // Проверяем лимит очереди
        guard pendingQueue.count < maxQueueSize else {
            print("[TaskQueueManager] Queue is full (\(maxQueueSize)), rejecting task: \(requestId)")
            return false
        }
        
        // Проверяем, не добавлена ли уже эта задача
        guard !pendingQueue.contains(requestId) && !activeTasks.contains(requestId) else {
            print("[TaskQueueManager] Task already in queue or active: \(requestId)")
            return true
        }
        
        pendingQueue.append(requestId)
        saveQueueToDisk()
        
        print("[TaskQueueManager] Task enqueued: \(requestId), queue size: \(pendingQueue.count), active: \(activeTasks.count)")
        
        // Пытаемся запустить задачи
        await processQueueInternal()
        
        return true
    }
    
    /// Вызывается при завершении задачи (успех или ошибка)
    func onTaskCompleted(_ requestId: String) async {
        if activeTasks.remove(requestId) != nil {
            print("[TaskQueueManager] Task completed: \(requestId), active: \(activeTasks.count)")
            await processQueueInternal()
        }
    }
    
    /// Удаляет задачу из очереди (если она ещё не запущена)
    func removeFromQueue(_ requestId: String) -> Bool {
        if let index = pendingQueue.firstIndex(of: requestId) {
            pendingQueue.remove(at: index)
            saveQueueToDisk()
            print("[TaskQueueManager] Task removed from queue: \(requestId)")
            return true
        }
        return false
    }
    
    /// Проверяет, находится ли задача в очереди
    func isTaskQueued(_ requestId: String) -> Bool {
        return pendingQueue.contains(requestId)
    }
    
    /// Проверяет, активна ли задача
    func isTaskActive(_ requestId: String) -> Bool {
        return activeTasks.contains(requestId)
    }
    
    /// Проверяет, находится ли задача в очереди или активна
    func isTaskPendingOrActive(_ requestId: String) -> Bool {
        return isTaskQueued(requestId) || isTaskActive(requestId)
    }
    
    /// Возвращает статистику очереди
    func getQueueStats() -> QueueStats {
        return QueueStats(
            pendingCount: pendingQueue.count,
            activeCount: activeTasks.count,
            maxConcurrent: maxConcurrentTasks,
            maxQueueSize: maxQueueSize
        )
    }
    
    /// Устанавливает максимальное количество одновременных задач
    func setMaxConcurrentTasks(_ count: Int) async {
        guard count >= 1 else {
            print("[TaskQueueManager] maxConcurrentTasks must be at least 1")
            return
        }
        maxConcurrentTasks = count
        
        // Если увеличили лимит, пытаемся запустить дополнительные задачи
        await processQueueInternal()
    }
    
    /// Устанавливает максимальный размер очереди
    func setMaxQueueSize(_ size: Int) {
        guard size >= 1 else {
            print("[TaskQueueManager] maxQueueSize must be at least 1")
            return
        }
        maxQueueSize = size
    }
    
    /// Очищает всю очередь
    func clearAll() -> Int {
        let totalCount = pendingQueue.count + activeTasks.count
        
        pendingQueue.removeAll()
        activeTasks.removeAll()
        saveQueueToDisk()
        
        print("[TaskQueueManager] Cleared all tasks: \(totalCount)")
        return totalCount
    }
    
    /// Принудительно обрабатывает очередь
    func processQueue() async {
        await processQueueInternal()
    }
    
    // MARK: - Private Methods
    
    private func processQueueInternal() async {
        while activeTasks.count < maxConcurrentTasks && !pendingQueue.isEmpty {
            let requestId = pendingQueue.removeFirst()
            activeTasks.insert(requestId)
            
            print("[TaskQueueManager] Started task: \(requestId), active: \(activeTasks.count), pending: \(pendingQueue.count)")
            
            // Запускаем задачу через callback
            if let callback = executeTaskCallback {
                Task {
                    await callback(requestId)
                }
            }
        }
        
        // Сохраняем очередь после изменений
        saveQueueToDisk()
    }
    
    // MARK: - Persistence
    
    private var queueFileURL: URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dirURL = documentsURL.appendingPathComponent("background_http_client", isDirectory: true)
        
        // Создаём директорию, если не существует
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

