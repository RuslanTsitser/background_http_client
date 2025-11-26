package com.tsitser.background_http_plugin.data.datasource

import android.content.Context
import androidx.work.Constraints
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import com.google.common.util.concurrent.ListenableFuture
import java.util.concurrent.ExecutionException

/**
 * Data source для работы с WorkManager
 */
class WorkManagerDataSource(private val context: Context) {

    private val workManager: WorkManager by lazy {
        WorkManager.getInstance(context)
    }

    // Кэш для результатов проверки состояния задач
    // Ключ: requestId, Значение: Pair(WorkStateResult, timestamp)
    private val workStateCache = mutableMapOf<String, Pair<WorkStateResult, Long>>()
    
    // Время жизни кэша в миллисекундах (1 секунда)
    private val cacheTtlMs = 1000L

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

    /**
     * Результат проверки состояния задачи в WorkManager
     */
    enum class WorkStateResult {
        /** Задача завершена успешно */
        SUCCEEDED,
        /** Задача завершена с ошибкой */
        FAILED,
        /** Задача еще выполняется (ENQUEUED, RUNNING, BLOCKED) */
        IN_PROGRESS,
        /** Задача не найдена в WorkManager */
        NOT_FOUND
    }

    /**
     * Проверяет актуальное состояние задачи в WorkManager
     * Использует кэширование для оптимизации производительности при большом количестве запросов
     * @param requestId ID запроса
     * @param forceRefresh если true, игнорирует кэш и выполняет проверку
     * @return WorkStateResult с актуальным состоянием задачи
     */
    suspend fun getWorkState(requestId: String, forceRefresh: Boolean = false): WorkStateResult {
        val currentTime = System.currentTimeMillis()
        
        // Проверяем кэш, если не требуется принудительное обновление
        if (!forceRefresh) {
            val cached = workStateCache[requestId]
            if (cached != null) {
                val (cachedResult, cachedTime) = cached
                // Если кэш еще актуален, возвращаем его
                if (currentTime - cachedTime < cacheTtlMs) {
                    return cachedResult
                }
            }
        }
        
        val result = try {
            val workInfosFuture: ListenableFuture<List<WorkInfo>> = workManager.getWorkInfosByTag("request_$requestId")
            val workInfoList = workInfosFuture.get()
            
            // Если список пуст, задача не найдена
            if (workInfoList.isEmpty()) {
                WorkStateResult.NOT_FOUND
            } else {
                // Проверяем все задачи с этим тегом
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
        
        // Сохраняем результат в кэш
        workStateCache[requestId] = Pair(result, currentTime)
        
        // Очищаем устаревшие записи из кэша (оставляем только последние 1000)
        if (workStateCache.size > 1000) {
            val entriesToRemove = workStateCache.entries
                .filter { currentTime - it.value.second > cacheTtlMs * 10 }
                .map { it.key }
                .take(500) // Удаляем половину устаревших
            entriesToRemove.forEach { workStateCache.remove(it) }
        }
        
        return result
    }
    
    /**
     * Очищает кэш состояния задач
     */
    fun clearWorkStateCache() {
        workStateCache.clear()
    }
}

