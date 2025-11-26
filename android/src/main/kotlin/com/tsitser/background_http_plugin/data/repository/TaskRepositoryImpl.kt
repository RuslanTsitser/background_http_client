package com.tsitser.background_http_plugin.data.repository

import android.content.Context
import com.tsitser.background_http_plugin.data.datasource.FileStorageDataSource
import com.tsitser.background_http_plugin.data.datasource.WorkManagerDataSource
import com.tsitser.background_http_plugin.data.mapper.RequestMapper
import com.tsitser.background_http_plugin.domain.entity.HttpRequest
import com.tsitser.background_http_plugin.domain.entity.RequestStatus
import com.tsitser.background_http_plugin.domain.entity.TaskInfo
import com.tsitser.background_http_plugin.domain.repository.TaskRepository
import java.util.UUID

/**
 * Реализация репозитория для работы с задачами HTTP запросов
 */
class TaskRepositoryImpl(
    private val context: Context
) : TaskRepository {

    private val fileStorage = FileStorageDataSource(context)
    private val workManager = WorkManagerDataSource(context)

    override suspend fun createTask(request: HttpRequest): TaskInfo {
        val requestId = request.requestId ?: RequestMapper.generateRequestId()
        val registrationDate = System.currentTimeMillis()

        // Сохраняем запрос в файл
        val taskInfo = fileStorage.saveRequest(request, requestId, registrationDate)

        // Запускаем задачу через WorkManager
        workManager.enqueueRequest(requestId)

        return taskInfo
    }

    override suspend fun getTaskInfo(requestId: String): TaskInfo? {
        return fileStorage.loadTaskInfo(requestId)
    }

    override suspend fun getTaskResponse(requestId: String): TaskInfo? {
        return fileStorage.loadTaskResponse(requestId)
    }

    override suspend fun cancelTask(requestId: String): Boolean? {
        if (!fileStorage.taskExists(requestId)) {
            return null
        }

        return try {
            workManager.cancelRequest(requestId)
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
            workManager.deleteRequest(requestId)
            val deleted = fileStorage.deleteTaskFiles(requestId)
            deleted
        } catch (e: Exception) {
            false
        }
    }
}

