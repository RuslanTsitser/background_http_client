package com.tsitser.background_http_plugin.data.repository

import android.content.Context
import com.tsitser.background_http_plugin.data.datasource.FileStorageDataSource
import com.tsitser.background_http_plugin.data.datasource.TaskQueueManager
import com.tsitser.background_http_plugin.data.datasource.WorkManagerDataSource
import com.tsitser.background_http_plugin.data.mapper.RequestMapper
import com.tsitser.background_http_plugin.domain.entity.HttpRequest
import com.tsitser.background_http_plugin.domain.entity.RequestStatus
import com.tsitser.background_http_plugin.domain.entity.TaskInfo
import com.tsitser.background_http_plugin.domain.repository.PendingTask
import com.tsitser.background_http_plugin.domain.repository.TaskRepository
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.UUID

/**
 * Repository implementation for working with HTTP request tasks.
 *
 * Uses TaskQueueManager to manage the task queue,
 * which helps avoid hangs when registering a large number of tasks.
 */
class TaskRepositoryImpl(
    private val context: Context
) : TaskRepository {

    private val fileStorage = FileStorageDataSource(context)
    private val workManager = WorkManagerDataSource(context)
    private val queueManager = TaskQueueManager.getInstance(context)
    
    // Mutex to protect from race conditions when creating requests with the same requestId
    private val createTaskMutex = Mutex()
    // Set to track requests that are currently being created
    private val creatingTasks = mutableSetOf<String>()

    override suspend fun createTask(request: HttpRequest): TaskInfo {
        val requestId = request.requestId ?: RequestMapper.generateRequestId()
        
        // Race-condition protection: use Mutex for synchronization
        return createTaskMutex.withLock {
            // Check whether a request with such requestId is already being created
            if (creatingTasks.contains(requestId)) {
                // Request is already being created in another thread; wait and return the existing one
                // Small delay to let creation finish in the other thread
                kotlinx.coroutines.delay(100)
                return@withLock getTaskInfo(requestId) 
                    ?: throw IllegalStateException("Failed to get task info after creation attempt")
            }
            
            // Optimization: Fast check if task exists before loading full info
            // This avoids expensive file read for new tasks
            if (fileStorage.taskExists(requestId)) {
                // Task exists, load full info
                val existingTask = fileStorage.loadTaskInfo(requestId)
                if (existingTask != null) {
                    // Request already exists
                    // Check whether it is in the queue or active
                    if (queueManager.isTaskPendingOrActive(requestId)) {
                        // Task is already in the queue or running
                        return@withLock existingTask
                    }
                    
                    // Check state in WorkManager
                    val workState = workManager.getWorkState(requestId, forceRefresh = false)
                    when (workState) {
                        WorkManagerDataSource.WorkStateResult.IN_PROGRESS,
                        WorkManagerDataSource.WorkStateResult.SUCCEEDED,
                        WorkManagerDataSource.WorkStateResult.FAILED -> {
                            // Request is already running or completed; return existing
                            return@withLock existingTask
                        }
                        WorkManagerDataSource.WorkStateResult.NOT_FOUND -> {
                            // Request exists in file storage, but not in WorkManager and not in the queue
                            // Enqueue it for execution
                            queueManager.enqueue(requestId)
                            return@withLock existingTask
                        }
                    }
                }
            }
            // Optimization: For new tasks (taskExists == false), skip WorkManager check
            // New tasks don't exist in WorkManager, so checking is unnecessary
            
            // Mark that the request is being created
            creatingTasks.add(requestId)
            
            try {
                val registrationDate = System.currentTimeMillis()
            
                // Save request to file
                val taskInfo = fileStorage.saveRequest(request, requestId, registrationDate)
            
                // Add task to the queue (instead of starting it directly in WorkManager)
                // TaskQueueManager itself will decide when to start the task
                queueManager.enqueue(requestId)
            
                return@withLock taskInfo
            } finally {
                // Remove from the set of requests being created
                creatingTasks.remove(requestId)
            }
        }
    }

    override suspend fun getTaskInfo(requestId: String): TaskInfo? {
        // Load task information from file
        var taskInfo = fileStorage.loadTaskInfo(requestId) ?: return null
        
        // If status is IN_PROGRESS, check actual state
        if (taskInfo.status == RequestStatus.IN_PROGRESS) {
            // First check if the response file exists – this is faster than querying WorkManager
            // If the response file exists, the request is completed
            val responseTaskInfo = fileStorage.loadTaskResponse(requestId)
            if (responseTaskInfo != null && responseTaskInfo.responseJson != null) {
                // Response file exists – request is completed
                // Update status from response
                val responseStatus = responseTaskInfo.responseJson["status"] as? Int
                if (responseStatus != null) {
                    val status = enumValues<RequestStatus>().firstOrNull { it.value == responseStatus }
                    if (status != null && status != RequestStatus.IN_PROGRESS) {
                        // Update status in status file for consistency
                        fileStorage.saveStatus(requestId, status)
                        // Notify queue that the task is completed
                        queueManager.onTaskCompleted(requestId)
                        // Return updated information
                        taskInfo = taskInfo.copy(status = status)
                    }
                }
            } else {
                // Check whether the task is in the queue (not started yet)
                if (queueManager.isTaskQueued(requestId)) {
                    // Task is in the queue; IN_PROGRESS status is correct
                    return taskInfo
                }
                
                // If there is no response file, check state in WorkManager.
                // This helps determine whether the task is finished but the response file is not yet written.
                // Use caching for optimization when there are many requests.
                val workState = workManager.getWorkState(requestId, forceRefresh = false)
                when (workState) {
                    WorkManagerDataSource.WorkStateResult.SUCCEEDED -> {
                        // WorkManager reports that the task has completed successfully,
                        // but the response file has not yet been created – it may still be writing.
                        // In this case we keep IN_PROGRESS so that on the next call
                        // the response file will be available and status will be updated from it.
                    }
                    WorkManagerDataSource.WorkStateResult.FAILED -> {
                        // WorkManager reports that the task has failed.
                        // Update status.
                        fileStorage.saveStatus(requestId, RequestStatus.FAILED)
                        // Notify queue that the task is completed
                        queueManager.onTaskCompleted(requestId)
                        taskInfo = taskInfo.copy(status = RequestStatus.FAILED)
                    }
                    WorkManagerDataSource.WorkStateResult.IN_PROGRESS -> {
                        // Task is indeed running in WorkManager.
                        // IN_PROGRESS status in the file is correct; do nothing.
                    }
                    WorkManagerDataSource.WorkStateResult.NOT_FOUND -> {
                        // Task not found in WorkManager and not in queue.
                        // It may have been lost – add it back to the queue.
                        if (!queueManager.isTaskPendingOrActive(requestId)) {
                            queueManager.enqueue(requestId)
                        }
                    }
                }
            }
        }
        
        return taskInfo
    }

    override suspend fun getTaskResponse(requestId: String): TaskInfo? {
        val response = fileStorage.loadTaskResponse(requestId)
        
        // If we received a response, notify the queue that the task is completed
        if (response?.responseJson != null) {
            queueManager.onTaskCompleted(requestId)
        }
        
        return response
    }

    override suspend fun cancelTask(requestId: String): Boolean? {
        if (!fileStorage.taskExists(requestId)) {
            return null
        }
        
        return try {
            // Remove from queue if the task is there
            queueManager.removeFromQueue(requestId)
            // Cancel in WorkManager if the task is there
            workManager.cancelRequest(requestId)
            // Notify queue that the task is completed
            queueManager.onTaskCompleted(requestId)
            fileStorage.saveStatus(requestId, RequestStatus.FAILED)
            true
        } catch (e: Exception) {
            false
        }
    }

    override suspend fun deleteTask(requestId: String): Boolean? {
        if (!fileStorage.taskExists(requestId)) {
            return null
        }
        
        return try {
            // Remove from queue
            queueManager.removeFromQueue(requestId)
            // Notify queue that the task is completed (in case it was active)
            queueManager.onTaskCompleted(requestId)
            workManager.deleteRequest(requestId)
            val deleted = fileStorage.deleteTaskFiles(requestId)
            deleted
        } catch (e: Exception) {
            false
        }
    }

    override suspend fun getPendingTasks(): List<PendingTask> {
        val pendingTasks = mutableListOf<PendingTask>()
        
        // Get all tasks from the file system
        val allTaskIds = fileStorage.getAllTaskIds()
        
        for (requestId in allTaskIds) {
            // Check that the status in file is IN_PROGRESS (not completed)
            val taskInfo = fileStorage.loadTaskInfo(requestId)
            if (taskInfo != null && taskInfo.status == RequestStatus.IN_PROGRESS) {
                // Check that there is no response yet (task is not completed)
                val response = fileStorage.loadTaskResponse(requestId)
                if (response == null || response.responseJson == null) {
                    // Add task to pending list
                    pendingTasks.add(PendingTask(
                        requestId = requestId,
                        registrationDate = taskInfo.registrationDate
                    ))
                }
            }
        }
        
        return pendingTasks
    }

    override suspend fun cancelAllTasks(): Int {
        // Clear our queue and WorkManager
        val queueCleared = queueManager.clearAll()
        workManager.cancelAllTasks()
        return queueCleared
    }
    
    /**
     * Gets queue statistics.
     */
    fun getQueueStats(): TaskQueueManager.QueueStats {
        return queueManager.getQueueStats()
    }
    
    /**
     * Sets the maximum number of concurrent tasks.
     */
    suspend fun setMaxConcurrentTasks(count: Int) {
        queueManager.setMaxConcurrentTasks(count)
    }
    
    /**
     * Sets the maximum queue size.
     */
    fun setMaxQueueSize(size: Int) {
        queueManager.setMaxQueueSize(size)
    }
    
    /**
     * Synchronizes the queue state.
     */
    suspend fun syncQueueState() {
        queueManager.syncQueueState(fileStorage)
    }
    
    /**
     * Forces queue processing.
     */
    suspend fun processQueue() {
        queueManager.processQueue()
    }
}
