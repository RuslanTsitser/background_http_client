package com.tsitser.background_http_plugin.data.datasource

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.OutOfQuotaPolicy
import java.util.concurrent.TimeUnit
import com.google.common.util.concurrent.ListenableFuture
import java.util.concurrent.ExecutionException

/**
 * Data source for working with WorkManager.
 */
class WorkManagerDataSource(private val context: Context) {

    private val workManager: WorkManager by lazy {
        WorkManager.getInstance(context)
    }

    // Cache for task state check results.
    // Key: requestId, Value: Pair(WorkStateResult, timestamp)
    private val workStateCache = mutableMapOf<String, Pair<WorkStateResult, Long>>()
    
    // Cache TTL in milliseconds (1 second)
    private val cacheTtlMs = 1000L

    /**
     * Enqueues an HTTP request task in WorkManager.
     * Configured for background execution when app is minimized.
     *
     * Note: On Android 12+ use ForegroundInfo inside Worker to keep
     * network access in background.
     */
    fun enqueueRequest(requestId: String) {
        val workRequest = OneTimeWorkRequestBuilder<HttpRequestWorker>()
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    // Allow execution even when device is in battery saver mode
                    .setRequiresBatteryNotLow(false)
                    // Allow execution even when storage is low
                    .setRequiresStorageNotLow(false)
                    .build()
            )
            .setInputData(
                androidx.work.Data.Builder()
                    .putString(HttpRequestWorker.KEY_REQUEST_ID, requestId)
                    .build()
            )
            .addTag("request_$requestId")
            // Try to start immediately while app is in foreground (Android 12+ restriction)
            .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            // Set backoff policy for retries (exponential backoff)
            .setBackoffCriteria(
                BackoffPolicy.EXPONENTIAL,
                30,
                TimeUnit.SECONDS
            )
            .build()

        // Use unique work name to prevent duplicates
        workManager.enqueueUniqueWork(
            "request_$requestId",
            ExistingWorkPolicy.KEEP,
            workRequest
        )
    }

    /**
     * Enqueues a queue processor worker to ensure pending tasks are drained
     * even if the app process is killed.
     */
    fun enqueueQueueProcessor() {
        val workRequest = OneTimeWorkRequestBuilder<QueueProcessorWorker>()
            .build()

        workManager.enqueueUniqueWork(
            "background_http_client_queue_processor",
            ExistingWorkPolicy.KEEP,
            workRequest
        )
    }
    
    /**
     * Cancels all tasks for the given request.
     */
    fun cancelRequest(requestId: String) {
        workManager.cancelAllWorkByTag("request_$requestId")
        workManager.cancelAllWorkByTag("request_${requestId}_retry")
        workManager.cancelAllWorkByTag("request_${requestId}_network_wait")
    }

    /**
     * Deletes all tasks for the given request.
     */
    fun deleteRequest(requestId: String) {
        cancelRequest(requestId)
    }

    /**
     * Result of checking a task state in WorkManager.
     */
    enum class WorkStateResult {
        /** Task completed successfully */
        SUCCEEDED,
        /** Task completed with error */
        FAILED,
        /** Task is still running (ENQUEUED, RUNNING, BLOCKED) */
        IN_PROGRESS,
        /** Task not found in WorkManager */
        NOT_FOUND
    }

    /**
     * Checks the current state of a task in WorkManager.
     * Uses caching for performance optimization with a large number of requests.
     * @param requestId request ID
     * @param forceRefresh if true, ignores cache and performs a fresh check
     * @return WorkStateResult with the current task state
     */
    suspend fun getWorkState(requestId: String, forceRefresh: Boolean = false): WorkStateResult {
        val currentTime = System.currentTimeMillis()
        
        // Check cache if a forced refresh is not required
        if (!forceRefresh) {
            val cached = workStateCache[requestId]
            if (cached != null) {
                val (cachedResult, cachedTime) = cached
                // If cache is still valid, return it
                if (currentTime - cachedTime < cacheTtlMs) {
                    return cachedResult
                }
            }
        }
        
        val result = try {
            val workInfosFuture: ListenableFuture<List<WorkInfo>> = workManager.getWorkInfosByTag("request_$requestId")
            val workInfoList = workInfosFuture.get()
            
            // If the list is empty, the task was not found
            if (workInfoList.isEmpty()) {
                WorkStateResult.NOT_FOUND
            } else {
                // Check all tasks with this tag
                var foundResult: WorkStateResult? = null
                for (workInfo in workInfoList) {
                    when (workInfo.state) {
                        WorkInfo.State.SUCCEEDED -> {
                            foundResult = WorkStateResult.SUCCEEDED
                            break
                        }
                        WorkInfo.State.FAILED -> {
                            foundResult = WorkStateResult.FAILED
                            break
                        }
                        WorkInfo.State.CANCELLED -> {
                            foundResult = WorkStateResult.FAILED
                            break
                        }
                        WorkInfo.State.ENQUEUED,
                        WorkInfo.State.RUNNING,
                        WorkInfo.State.BLOCKED -> {
                            foundResult = WorkStateResult.IN_PROGRESS
                            break
                        }
                    }
                }
                foundResult ?: WorkStateResult.NOT_FOUND
            }
        } catch (e: ExecutionException) {
            WorkStateResult.NOT_FOUND
        } catch (e: InterruptedException) {
            WorkStateResult.NOT_FOUND
        } catch (e: Exception) {
            WorkStateResult.NOT_FOUND
        }
        
        // Save result to cache
        workStateCache[requestId] = Pair(result, currentTime)
        
        // Clean up stale cache entries (keep only the latest 1000)
        if (workStateCache.size > 1000) {
            val entriesToRemove = workStateCache.entries
                .filter { currentTime - it.value.second > cacheTtlMs * 10 }
                .map { it.key }
                .take(500) // Remove half of the stale entries
            entriesToRemove.forEach { workStateCache.remove(it) }
        }
        
        return result
    }
    
    /**
     * Clears task state cache.
     */
    fun clearWorkStateCache() {
        workStateCache.clear()
    }

    /**
     * Returns all ENQUEUED tasks for the given requestId, if any.
     */
    suspend fun getEnqueuedWorkInfo(requestId: String): WorkInfo? {
        return try {
            val workInfosFuture: ListenableFuture<List<WorkInfo>> = workManager.getWorkInfosByTag("request_$requestId")
            val workInfos = workInfosFuture.get()
            workInfos.firstOrNull { it.state == WorkInfo.State.ENQUEUED }
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Checks whether there is an active task (ENQUEUED or RUNNING) for the given requestId.
     */
    suspend fun hasActiveWork(requestId: String): Boolean {
        return try {
            val workInfosFuture: ListenableFuture<List<WorkInfo>> = workManager.getWorkInfosByTag("request_$requestId")
            val workInfos = workInfosFuture.get()
            workInfos.any { 
                it.state == WorkInfo.State.ENQUEUED || 
                it.state == WorkInfo.State.RUNNING ||
                it.state == WorkInfo.State.BLOCKED
            }
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Cancels all tasks.
     * @return number of cancelled tasks (always 0, since the exact count is unknown)
     */
    suspend fun cancelAllTasks(): Int {
        return try {
            // Cancel all tasks
            workManager.cancelAllWork()
            // Return 0 since we cannot precisely count cancelled tasks
            // without first querying all tasks
            0
        } catch (e: Exception) {
            0
        }
    }
}

