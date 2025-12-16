package com.tsitser.background_http_plugin.data.datasource

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONArray
import java.io.File
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.CopyOnWriteArraySet

/**
 * Менеджер очереди задач для управления количеством одновременных запросов
 * 
 * Решает проблему зависания при регистрации большого числа задач в WorkManager.
 * Вместо того чтобы сразу регистрировать все задачи в WorkManager, 
 * TaskQueueManager держит их в своей очереди и запускает порциями.
 */
class TaskQueueManager(private val context: Context) {
    
    companion object {
        private const val TAG = "TaskQueueManager"
        private const val QUEUE_FILE_NAME = "pending_queue.json"
        private const val DEFAULT_MAX_CONCURRENT_TASKS = 30
        private const val DEFAULT_MAX_QUEUE_SIZE = 10000
        
        @Volatile
        private var instance: TaskQueueManager? = null
        
        fun getInstance(context: Context): TaskQueueManager {
            return instance ?: synchronized(this) {
                instance ?: TaskQueueManager(context.applicationContext).also { instance = it }
            }
        }
    }
    
    private val workManager = WorkManagerDataSource(context)
    
    // Очередь ожидающих задач (только requestId, данные на диске)
    private val pendingQueue = ConcurrentLinkedQueue<String>()
    
    // Множество активных задач (запущенных в WorkManager)
    private val activeTasks = CopyOnWriteArraySet<String>()
    
    // Mutex для синхронизации операций с очередью
    private val queueMutex = Mutex()
    
    // Корутина для фоновых операций
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    
    // Настройки
    @Volatile
    var maxConcurrentTasks: Int = DEFAULT_MAX_CONCURRENT_TASKS
        private set
    
    @Volatile
    var maxQueueSize: Int = DEFAULT_MAX_QUEUE_SIZE
        private set
    
    // Файл для персистентного хранения очереди
    private val queueFile: File
        get() {
            val dir = File(context.filesDir, "background_http_client")
            if (!dir.exists()) dir.mkdirs()
            return File(dir, QUEUE_FILE_NAME)
        }
    
    init {
        // Восстанавливаем очередь при инициализации
        restoreQueue()
    }
    
    /**
     * Добавляет задачу в очередь
     * @param requestId ID задачи
     * @return true если задача добавлена, false если очередь переполнена
     */
    suspend fun enqueue(requestId: String): Boolean = queueMutex.withLock {
        // Проверяем, не превышен ли лимит очереди
        if (pendingQueue.size >= maxQueueSize) {
            Log.w(TAG, "Queue is full ($maxQueueSize), rejecting task: $requestId")
            return@withLock false
        }
        
        // Проверяем, не добавлена ли уже эта задача
        if (pendingQueue.contains(requestId) || activeTasks.contains(requestId)) {
            Log.d(TAG, "Task already in queue or active: $requestId")
            return@withLock true
        }
        
        pendingQueue.offer(requestId)
        saveQueueAsync()
        
        Log.d(TAG, "Task enqueued: $requestId, queue size: ${pendingQueue.size}, active: ${activeTasks.size}")
        
        // Пытаемся запустить задачи
        processQueueInternal()
        
        return@withLock true
    }
    
    /**
     * Вызывается при завершении задачи (успех или ошибка)
     */
    suspend fun onTaskCompleted(requestId: String) = queueMutex.withLock {
        if (activeTasks.remove(requestId)) {
            Log.d(TAG, "Task completed: $requestId, active: ${activeTasks.size}")
            processQueueInternal()
        }
    }
    
    /**
     * Удаляет задачу из очереди (если она ещё не запущена)
     */
    suspend fun removeFromQueue(requestId: String): Boolean = queueMutex.withLock {
        val removed = pendingQueue.remove(requestId)
        if (removed) {
            saveQueueAsync()
            Log.d(TAG, "Task removed from queue: $requestId")
        }
        return@withLock removed
    }
    
    /**
     * Проверяет, находится ли задача в очереди или активна
     */
    fun isTaskQueued(requestId: String): Boolean {
        return pendingQueue.contains(requestId)
    }
    
    fun isTaskActive(requestId: String): Boolean {
        return activeTasks.contains(requestId)
    }
    
    fun isTaskPendingOrActive(requestId: String): Boolean {
        return isTaskQueued(requestId) || isTaskActive(requestId)
    }
    
    /**
     * Возвращает статистику очереди
     */
    fun getQueueStats(): QueueStats {
        return QueueStats(
            pendingCount = pendingQueue.size,
            activeCount = activeTasks.size,
            maxConcurrent = maxConcurrentTasks,
            maxQueueSize = maxQueueSize
        )
    }
    
    /**
     * Устанавливает максимальное количество одновременных задач
     */
    suspend fun setMaxConcurrentTasks(count: Int) {
        if (count < 1) {
            throw IllegalArgumentException("maxConcurrentTasks must be at least 1")
        }
        maxConcurrentTasks = count
        
        // Если увеличили лимит, пытаемся запустить дополнительные задачи
        queueMutex.withLock {
            processQueueInternal()
        }
    }
    
    /**
     * Устанавливает максимальный размер очереди
     */
    fun setMaxQueueSize(size: Int) {
        if (size < 1) {
            throw IllegalArgumentException("maxQueueSize must be at least 1")
        }
        maxQueueSize = size
    }
    
    /**
     * Очищает всю очередь и отменяет активные задачи
     */
    suspend fun clearAll(): Int = queueMutex.withLock {
        val totalCount = pendingQueue.size + activeTasks.size
        
        // Отменяем активные задачи в WorkManager
        for (requestId in activeTasks) {
            workManager.cancelRequest(requestId)
        }
        
        pendingQueue.clear()
        activeTasks.clear()
        saveQueueAsync()
        
        Log.d(TAG, "Cleared all tasks: $totalCount")
        return@withLock totalCount
    }
    
    /**
     * Принудительно обрабатывает очередь
     */
    suspend fun processQueue() = queueMutex.withLock {
        processQueueInternal()
    }
    
    // Внутренний метод обработки очереди (должен вызываться под mutex)
    private fun processQueueInternal() {
        while (activeTasks.size < maxConcurrentTasks && pendingQueue.isNotEmpty()) {
            val requestId = pendingQueue.poll() ?: break
            
            activeTasks.add(requestId)
            workManager.enqueueRequest(requestId)
            
            Log.d(TAG, "Started task: $requestId, active: ${activeTasks.size}, pending: ${pendingQueue.size}")
        }
        
        // Сохраняем очередь после изменений
        saveQueueAsync()
    }
    
    // Сохраняет очередь на диск асинхронно
    private fun saveQueueAsync() {
        scope.launch {
            try {
                val jsonArray = JSONArray()
                pendingQueue.forEach { jsonArray.put(it) }
                queueFile.writeText(jsonArray.toString())
            } catch (e: Exception) {
                Log.e(TAG, "Failed to save queue to disk", e)
            }
        }
    }
    
    // Восстанавливает очередь с диска
    private fun restoreQueue() {
        try {
            if (!queueFile.exists()) {
                Log.d(TAG, "No queue file found, starting fresh")
                return
            }
            
            val json = queueFile.readText()
            if (json.isBlank()) return
            
            val jsonArray = JSONArray(json)
            var restoredCount = 0
            
            for (i in 0 until jsonArray.length()) {
                val requestId = jsonArray.getString(i)
                pendingQueue.offer(requestId)
                restoredCount++
            }
            
            Log.d(TAG, "Restored $restoredCount tasks from disk")
            
            // Запускаем обработку восстановленной очереди
            scope.launch {
                queueMutex.withLock {
                    processQueueInternal()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to restore queue from disk", e)
        }
    }
    
    /**
     * Синхронизирует состояние очереди с реальным состоянием задач
     * Вызывается для очистки "зависших" задач
     */
    suspend fun syncQueueState(fileStorage: FileStorageDataSource) = queueMutex.withLock {
        val tasksToRemove = mutableListOf<String>()
        
        // Проверяем активные задачи
        for (requestId in activeTasks) {
            val workState = workManager.getWorkState(requestId, forceRefresh = true)
            when (workState) {
                WorkManagerDataSource.WorkStateResult.SUCCEEDED,
                WorkManagerDataSource.WorkStateResult.FAILED -> {
                    tasksToRemove.add(requestId)
                }
                WorkManagerDataSource.WorkStateResult.NOT_FOUND -> {
                    // Задача потеряна, перезапускаем
                    Log.w(TAG, "Task lost in WorkManager, re-enqueueing: $requestId")
                    workManager.enqueueRequest(requestId)
                }
                WorkManagerDataSource.WorkStateResult.IN_PROGRESS -> {
                    // Всё OK
                }
            }
        }
        
        // Удаляем завершённые из активных
        tasksToRemove.forEach { activeTasks.remove(it) }
        
        // Проверяем pending задачи - возможно файлы запросов удалены
        val pendingToRemove = mutableListOf<String>()
        for (requestId in pendingQueue) {
            if (!fileStorage.taskExists(requestId)) {
                pendingToRemove.add(requestId)
                Log.w(TAG, "Request file not found for pending task, removing: $requestId")
            }
        }
        pendingToRemove.forEach { pendingQueue.remove(it) }
        
        if (tasksToRemove.isNotEmpty() || pendingToRemove.isNotEmpty()) {
            saveQueueAsync()
            processQueueInternal()
        }
        
        Log.d(TAG, "Queue synced: removed ${tasksToRemove.size} completed, ${pendingToRemove.size} orphaned")
    }
    
    data class QueueStats(
        val pendingCount: Int,
        val activeCount: Int,
        val maxConcurrent: Int,
        val maxQueueSize: Int
    ) {
        fun toMap(): Map<String, Any> = mapOf(
            "pendingCount" to pendingCount,
            "activeCount" to activeCount,
            "maxConcurrent" to maxConcurrent,
            "maxQueueSize" to maxQueueSize
        )
    }
}

