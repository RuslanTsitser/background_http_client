package com.tsitser.background_http_plugin.data.datasource

import android.content.Context
import androidx.work.Constraints
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager

/**
 * Data source для работы с WorkManager
 */
class WorkManagerDataSource(private val context: Context) {

    private val workManager: WorkManager by lazy {
        WorkManager.getInstance(context)
    }

    /**
     * Запускает задачу HTTP запроса через WorkManager
     */
    fun enqueueRequest(requestId: String) {
        val workRequest = OneTimeWorkRequestBuilder<HttpRequestWorker>()
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()
            )
            .setInputData(
                androidx.work.Data.Builder()
                    .putString(HttpRequestWorker.KEY_REQUEST_ID, requestId)
                    .build()
            )
            .addTag("request_$requestId")
            .build()

        workManager.enqueue(workRequest)
    }

    /**
     * Отменяет все задачи для данного запроса
     */
    fun cancelRequest(requestId: String) {
        workManager.cancelAllWorkByTag("request_$requestId")
        workManager.cancelAllWorkByTag("request_${requestId}_retry")
        workManager.cancelAllWorkByTag("request_${requestId}_network_wait")
    }

    /**
     * Удаляет все задачи для данного запроса
     */
    fun deleteRequest(requestId: String) {
        cancelRequest(requestId)
    }
}

