package com.tsitser.background_http_plugin.data.datasource

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

/**
 * Worker that triggers queue processing when app process is killed.
 */
class QueueProcessorWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    companion object {
        private const val TAG = "QueueProcessorWorker"
    }

    override suspend fun doWork(): Result {
        return try {
            val queueManager = TaskQueueManager.getInstance(applicationContext)
            queueManager.processQueue()
            Log.d(TAG, "Queue processing triggered")
            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Queue processing failed", e)
            Result.retry()
        }
    }
}
