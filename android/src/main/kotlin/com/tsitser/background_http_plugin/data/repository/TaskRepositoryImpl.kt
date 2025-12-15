package com.tsitser.background_http_plugin.data.repository

import android.content.Context
import androidx.work.WorkInfo
import com.tsitser.background_http_plugin.data.datasource.FileStorageDataSource
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
 * Реализация репозитория для работы с задачами HTTP запросов
 */
class TaskRepositoryImpl(
    private val context: Context
) : TaskRepository {

    private val fileStorage = FileStorageDataSource(context)
    private val workManager = WorkManagerDataSource(context)
    
    // Mutex для защиты от race condition при создании запросов с одинаковым requestId
    private val createTaskMutex = Mutex()
    // Map для отслеживания запросов, которые находятся в процессе создания
    private val creatingTasks = mutableSetOf<String>()

    override suspend fun createTask(request: HttpRequest): TaskInfo {
        val requestId = request.requestId ?: RequestMapper.generateRequestId()
        
        // Защита от race condition: используем Mutex для синхронизации
        return createTaskMutex.withLock {
            // Проверяем, не создается ли уже запрос с таким requestId
            if (creatingTasks.contains(requestId)) {
                // Запрос уже создается в другом потоке, ждем и возвращаем существующий
                // Небольшая задержка для завершения создания в другом потоке
                kotlinx.coroutines.delay(100)
                return@withLock getTaskInfo(requestId) 
                    ?: throw IllegalStateException("Failed to get task info after creation attempt")
            }
            
            // Проверяем, существует ли уже запрос с таким requestId
            val existingTask = fileStorage.loadTaskInfo(requestId)
            if (existingTask != null) {
                // Запрос уже существует
                val workState = workManager.getWorkState(requestId, forceRefresh = false)
                when (workState) {
                    WorkManagerDataSource.WorkStateResult.IN_PROGRESS,
                    WorkManagerDataSource.WorkStateResult.SUCCEEDED,
                    WorkManagerDataSource.WorkStateResult.FAILED -> {
                        // Запрос уже выполняется или завершен, возвращаем существующий
                        return@withLock existingTask
                    }
                    WorkManagerDataSource.WorkStateResult.NOT_FOUND -> {
                        // Запрос существует в файловой системе, но не найден в WorkManager
                        // Возможно, он был удален из WorkManager, но файлы остались
                        // Пересоздаем задачу в WorkManager
                        workManager.enqueueRequest(requestId)
                        return@withLock existingTask
                    }
                }
            }
            
            // Помечаем, что запрос создается
            creatingTasks.add(requestId)
            
            try {
                val registrationDate = System.currentTimeMillis()

                // Сохраняем запрос в файл
                val taskInfo = fileStorage.saveRequest(request, requestId, registrationDate)

                // Запускаем задачу через WorkManager
                workManager.enqueueRequest(requestId)

                return@withLock taskInfo
            } finally {
                // Убираем из множества создающихся запросов
                creatingTasks.remove(requestId)
            }
        }
    }

    override suspend fun getTaskInfo(requestId: String): TaskInfo? {
        // Загружаем информацию о задаче из файла
        var taskInfo = fileStorage.loadTaskInfo(requestId) ?: return null
        
        // Если статус IN_PROGRESS, проверяем актуальное состояние
        if (taskInfo.status == RequestStatus.IN_PROGRESS) {
            // Сначала проверяем наличие файла ответа - это быстрее, чем проверка WorkManager
            // Если файл ответа существует, значит запрос завершен
            val responseTaskInfo = fileStorage.loadTaskResponse(requestId)
            if (responseTaskInfo != null && responseTaskInfo.responseJson != null) {
                // Файл ответа существует, значит запрос завершен
                // Обновляем статус из ответа
                val responseStatus = responseTaskInfo.responseJson["status"] as? Int
                if (responseStatus != null) {
                    val status = enumValues<RequestStatus>().firstOrNull { it.value == responseStatus }
                    if (status != null && status != RequestStatus.IN_PROGRESS) {
                        // Обновляем статус в файле статуса для консистентности
                        fileStorage.saveStatus(requestId, status)
                        // Возвращаем обновленную информацию
                        taskInfo = taskInfo.copy(status = status)
                    }
                }
            } else {
                // Если файла ответа нет, проверяем состояние в WorkManager
                // Используем forceRefresh для получения актуального состояния
                val (workState, workInfoState) = workManager.getDetailedWorkState(requestId)
                
                when (workState) {
                    WorkManagerDataSource.WorkStateResult.SUCCEEDED -> {
                        // WorkManager сообщает, что задача завершена успешно,
                        // но файл ответа еще не создан - возможно, он еще записывается.
                        // В этом случае оставляем статус IN_PROGRESS, чтобы при следующем вызове
                        // файл ответа уже был доступен и статус обновится из него
                    }
                    WorkManagerDataSource.WorkStateResult.FAILED -> {
                        // WorkManager сообщает, что задача завершена с ошибкой
                        // Обновляем статус
                        fileStorage.saveStatus(requestId, RequestStatus.FAILED)
                        taskInfo = taskInfo.copy(status = RequestStatus.FAILED)
                    }
                    WorkManagerDataSource.WorkStateResult.IN_PROGRESS -> {
                        // Проверяем, не зависла ли задача
                        // Задача считается зависшей, если она в ENQUEUED или BLOCKED дольше queueTimeout
                        if (workInfoState == WorkInfo.State.ENQUEUED || workInfoState == WorkInfo.State.BLOCKED) {
                            val queueTimeout = fileStorage.loadQueueTimeout(requestId)
                            val currentTime = System.currentTimeMillis()
                            val taskAge = currentTime - taskInfo.registrationDate
                            
                            // Если задача зависла дольше queueTimeout, пересоздаем её
                            if (taskAge > queueTimeout * 1000L) {
                                android.util.Log.w("TaskRepositoryImpl", "Task $requestId is stuck in ${workInfoState} for ${taskAge}ms, recreating...")
                                // Отменяем старую задачу
                                workManager.cancelRequest(requestId)
                                // Пересоздаем задачу
                                workManager.enqueueRequest(requestId)
                                // Обновляем дату регистрации
                                fileStorage.saveStatus(requestId, RequestStatus.IN_PROGRESS, currentTime)
                                taskInfo = taskInfo.copy(registrationDate = currentTime)
                            }
                        }
                        // Задача действительно выполняется в WorkManager
                        // Статус IN_PROGRESS в файле корректный
                    }
                    WorkManagerDataSource.WorkStateResult.NOT_FOUND -> {
                        // Задача не найдена в WorkManager
                        // Проверяем возраст задачи - если она старая, пересоздаем её
                        val queueTimeout = fileStorage.loadQueueTimeout(requestId)
                        val currentTime = System.currentTimeMillis()
                        val taskAge = currentTime - taskInfo.registrationDate
                        
                        // Если задача не найдена в WorkManager, но она недавно создана, пересоздаем
                        // Если задача старая (старше queueTimeout), возможно она уже завершилась, но файл ответа потерян
                        if (taskAge < queueTimeout * 1000L) {
                            // Задача недавно создана, но не найдена в WorkManager - пересоздаем
                            android.util.Log.w("TaskRepositoryImpl", "Task $requestId not found in WorkManager, recreating...")
                            workManager.enqueueRequest(requestId)
                            fileStorage.saveStatus(requestId, RequestStatus.IN_PROGRESS, currentTime)
                            taskInfo = taskInfo.copy(registrationDate = currentTime)
                        } else {
                            // Задача старая и не найдена в WorkManager - возможно, она зависла
                            // Помечаем как FAILED
                            android.util.Log.w("TaskRepositoryImpl", "Task $requestId is old (${taskAge}ms) and not found in WorkManager, marking as FAILED")
                            fileStorage.saveStatus(requestId, RequestStatus.FAILED)
                            taskInfo = taskInfo.copy(status = RequestStatus.FAILED)
                        }
                    }
                }
            }
        }
        
        return taskInfo
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

    override suspend fun getPendingTasks(): List<PendingTask> {
        val pendingTasks = mutableListOf<PendingTask>()
        
        // Получаем все задачи из файловой системы
        val allTaskIds = fileStorage.getAllTaskIds()
        
        for (requestId in allTaskIds) {
            // Проверяем, что статус в файле IN_PROGRESS (не завершена)
            val taskInfo = fileStorage.loadTaskInfo(requestId)
            if (taskInfo != null && taskInfo.status == RequestStatus.IN_PROGRESS) {
                // Проверяем, что нет ответа (задача еще не завершена)
                val response = fileStorage.loadTaskResponse(requestId)
                if (response == null || response.responseJson == null) {
                    // Проверяем состояние задачи в WorkManager
                    val (workState, workInfoState) = workManager.getDetailedWorkState(requestId)
                    
                    when (workState) {
                        WorkManagerDataSource.WorkStateResult.IN_PROGRESS -> {
                            // Проверяем, не зависла ли задача
                            if (workInfoState == WorkInfo.State.ENQUEUED || workInfoState == WorkInfo.State.BLOCKED) {
                                val queueTimeout = fileStorage.loadQueueTimeout(requestId)
                                val currentTime = System.currentTimeMillis()
                                val taskAge = currentTime - taskInfo.registrationDate
                                
                                // Если задача зависла дольше queueTimeout, пересоздаем её
                                if (taskAge > queueTimeout * 1000L) {
                                    android.util.Log.w("TaskRepositoryImpl", "Task $requestId is stuck in ${workInfoState} for ${taskAge}ms in getPendingTasks, recreating...")
                                    // Отменяем старую задачу
                                    workManager.cancelRequest(requestId)
                                    // Пересоздаем задачу
                                    workManager.enqueueRequest(requestId)
                                    // Обновляем дату регистрации
                                    fileStorage.saveStatus(requestId, RequestStatus.IN_PROGRESS, currentTime)
                                    // Добавляем в pending с обновленной датой
                                    pendingTasks.add(PendingTask(
                                        requestId = requestId,
                                        registrationDate = currentTime
                                    ))
                                } else {
                                    // Задача еще не зависла, добавляем в pending
                                    pendingTasks.add(PendingTask(
                                        requestId = requestId,
                                        registrationDate = taskInfo.registrationDate
                                    ))
                                }
                            } else {
                                // Задача выполняется (RUNNING), добавляем в pending
                                pendingTasks.add(PendingTask(
                                    requestId = requestId,
                                    registrationDate = taskInfo.registrationDate
                                ))
                            }
                        }
                        WorkManagerDataSource.WorkStateResult.NOT_FOUND -> {
                            // Задача не найдена в WorkManager
                            val queueTimeout = fileStorage.loadQueueTimeout(requestId)
                            val currentTime = System.currentTimeMillis()
                            val taskAge = currentTime - taskInfo.registrationDate
                            
                            // Если задача недавно создана, но не найдена в WorkManager - пересоздаем
                            if (taskAge < queueTimeout * 1000L) {
                                android.util.Log.w("TaskRepositoryImpl", "Task $requestId not found in WorkManager in getPendingTasks, recreating...")
                                workManager.enqueueRequest(requestId)
                                fileStorage.saveStatus(requestId, RequestStatus.IN_PROGRESS, currentTime)
                                // Добавляем в pending с обновленной датой
                                pendingTasks.add(PendingTask(
                                    requestId = requestId,
                                    registrationDate = currentTime
                                ))
                            } else {
                                // Задача старая и не найдена - возможно, она зависла
                                // Помечаем как FAILED, не добавляем в pending
                                android.util.Log.w("TaskRepositoryImpl", "Task $requestId is old (${taskAge}ms) and not found in WorkManager in getPendingTasks, marking as FAILED")
                                fileStorage.saveStatus(requestId, RequestStatus.FAILED)
                            }
                        }
                        WorkManagerDataSource.WorkStateResult.SUCCEEDED,
                        WorkManagerDataSource.WorkStateResult.FAILED -> {
                            // Задача завершена, не добавляем в pending
                            // Статус будет обновлен при следующем вызове getTaskInfo
                        }
                    }
                }
            }
        }
        
        return pendingTasks
    }

    override suspend fun cancelAllTasks(): Int {
        return workManager.cancelAllTasks()
    }
}

