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
 * Task queue manager for controlling the number of concurrent requests.
 *
 * Solves the problem of hangs when registering a large number of tasks in WorkManager.
 * Instead of registering all tasks in WorkManager at once,
 * TaskQueueManager keeps them in its own queue and starts them in batches.
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
    
    // Queue of pending tasks (only requestId, data is on disk)
    private val pendingQueue = ConcurrentLinkedQueue<String>()
    
    // Set of active tasks (started in WorkManager)
    private val activeTasks = CopyOnWriteArraySet<String>()
    
    // Mutex for synchronizing queue operations
    private val queueMutex = Mutex()
    
    // Coroutine scope for background operations
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    
    // Settings
    @Volatile
    var maxConcurrentTasks: Int = DEFAULT_MAX_CONCURRENT_TASKS
        private set
    
    @Volatile
    var maxQueueSize: Int = DEFAULT_MAX_QUEUE_SIZE
        private set
    
    // File for persistent queue storage
    private val queueFile: File
        get() {
            val dir = File(context.filesDir, "background_http_client")
            if (!dir.exists()) dir.mkdirs()
            return File(dir, QUEUE_FILE_NAME)
        }
    
    init {
        // Restore queue on initialization
        restoreQueue()
    }
    
    /**
     * Adds a task to the queue.
     * @param requestId task ID
     * @return true if the task was added, false if the queue is full
     */
    suspend fun enqueue(requestId: String): Boolean = queueMutex.withLock {
        // Check that the queue size limit is not exceeded
        if (pendingQueue.size >= maxQueueSize) {
            Log.w(TAG, "Queue is full ($maxQueueSize), rejecting task: $requestId")
            return@withLock false
        }
        
        // Check that this task has not already been added
        if (pendingQueue.contains(requestId) || activeTasks.contains(requestId)) {
            Log.d(TAG, "Task already in queue or active: $requestId")
            return@withLock true
        }
        
        pendingQueue.offer(requestId)
        saveQueueAsync()
        
        Log.d(TAG, "Task enqueued: $requestId, queue size: ${pendingQueue.size}, active: ${activeTasks.size}")
        
        // Try to start tasks
        processQueueInternal()
        
        return@withLock true
    }
    
    /**
     * Called when a task is completed (success or error).
     */
    suspend fun onTaskCompleted(requestId: String) = queueMutex.withLock {
        if (activeTasks.remove(requestId)) {
            Log.d(TAG, "Task completed: $requestId, active: ${activeTasks.size}")
            processQueueInternal()
        }
    }
    
    /**
     * Removes a task from the queue (if it has not been started yet).
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
     * Checks whether a task is pending or active.
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
     * Returns queue statistics.
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
     * Sets the maximum number of concurrent tasks.
     */
    suspend fun setMaxConcurrentTasks(count: Int) {
        if (count < 1) {
            throw IllegalArgumentException("maxConcurrentTasks must be at least 1")
        }
        maxConcurrentTasks = count
        
        // If the limit was increased, try to start additional tasks
        queueMutex.withLock {
            processQueueInternal()
        }
    }
    
    /**
     * Sets the maximum queue size.
     */
    fun setMaxQueueSize(size: Int) {
        if (size < 1) {
            throw IllegalArgumentException("maxQueueSize must be at least 1")
        }
        maxQueueSize = size
    }
    
    /**
     * Clears the entire queue and cancels active tasks.
     */
    suspend fun clearAll(): Int = queueMutex.withLock {
        val totalCount = pendingQueue.size + activeTasks.size
        
        // Cancel active tasks in WorkManager
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
     * Forces queue processing.
     */
    suspend fun processQueue() = queueMutex.withLock {
        processQueueInternal()
    }
    
    // Internal queue processing method (must be called under mutex)
    private fun processQueueInternal() {
        while (activeTasks.size < maxConcurrentTasks && pendingQueue.isNotEmpty()) {
            val requestId = pendingQueue.poll() ?: break
            
            activeTasks.add(requestId)
            workManager.enqueueRequest(requestId)
            
            Log.d(TAG, "Started task: $requestId, active: ${activeTasks.size}, pending: ${pendingQueue.size}")
        }
        
        // Persist queue after changes
        saveQueueAsync()
    }
    
    // Persists the queue to disk asynchronously
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
    
    // Restores the queue from disk
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
            
            // Start processing of the restored queue
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
     * Synchronizes the queue state with the actual task state.
     * Called to clean up "stuck" tasks.
     */
    suspend fun syncQueueState(fileStorage: FileStorageDataSource) = queueMutex.withLock {
        val tasksToRemove = mutableListOf<String>()
        
        // Check active tasks
        for (requestId in activeTasks) {
            val workState = workManager.getWorkState(requestId, forceRefresh = true)
            when (workState) {
                WorkManagerDataSource.WorkStateResult.SUCCEEDED,
                WorkManagerDataSource.WorkStateResult.FAILED -> {
                    tasksToRemove.add(requestId)
                }
                WorkManagerDataSource.WorkStateResult.NOT_FOUND -> {
                    // Task is lost, re-enqueue
                    Log.w(TAG, "Task lost in WorkManager, re-enqueueing: $requestId")
                    workManager.enqueueRequest(requestId)
                }
                WorkManagerDataSource.WorkStateResult.IN_PROGRESS -> {
                    // Everything OK
                }
            }
        }
        
        // Remove completed from active
        tasksToRemove.forEach { activeTasks.remove(it) }
        
        // Check pending tasks – request files may have been deleted
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

