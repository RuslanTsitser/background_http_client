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
 * Реализация репозитория для работы с задачами HTTP запросов
 * 
 * Использует TaskQueueManager для управления очередью задач,
 * что позволяет избежать зависания при регистрации большого числа задач.
 */
class TaskRepositoryImpl(
    private val context: Context
) : TaskRepository {

    private val fileStorage = FileStorageDataSource(context)
    private val workManager = WorkManagerDataSource(context)
    private val queueManager = TaskQueueManager.getInstance(context)
    
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
                // Проверяем, находится ли он в очереди или активен
                if (queueManager.isTaskPendingOrActive(requestId)) {
                    // Задача уже в очереди или выполняется
                    return@withLock existingTask
                }
                
                // Проверяем состояние в WorkManager
                val workState = workManager.getWorkState(requestId, forceRefresh = false)
                when (workState) {
                    WorkManagerDataSource.WorkStateResult.IN_PROGRESS,
                    WorkManagerDataSource.WorkStateResult.SUCCEEDED,
                    WorkManagerDataSource.WorkStateResult.FAILED -> {
                        // Запрос уже выполняется или завершен, возвращаем существующий
                        return@withLock existingTask
                    }
                    WorkManagerDataSource.WorkStateResult.NOT_FOUND -> {
                        // Запрос существует в файловой системе, но не найден в WorkManager и не в очереди
                        // Добавляем в очередь для выполнения
                        queueManager.enqueue(requestId)
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

                // Добавляем задачу в очередь (вместо прямого запуска в WorkManager)
                // TaskQueueManager сам решит, когда запустить задачу
                queueManager.enqueue(requestId)

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
                        // Уведомляем очередь о завершении задачи
                        queueManager.onTaskCompleted(requestId)
                        // Возвращаем обновленную информацию
                        taskInfo = taskInfo.copy(status = status)
                    }
                }
            } else {
                // Проверяем, находится ли задача в очереди (ещё не запущена)
                if (queueManager.isTaskQueued(requestId)) {
                    // Задача в очереди, статус IN_PROGRESS корректен
                    return taskInfo
                }
                
                // Если файла ответа нет, проверяем состояние в WorkManager
                // Это поможет определить, завершена ли задача, но файл ответа еще не записан
                // Используем кэширование для оптимизации при большом количестве запросов
                val workState = workManager.getWorkState(requestId, forceRefresh = false)
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
                        // Уведомляем очередь о завершении задачи
                        queueManager.onTaskCompleted(requestId)
                        taskInfo = taskInfo.copy(status = RequestStatus.FAILED)
                    }
                    WorkManagerDataSource.WorkStateResult.IN_PROGRESS -> {
                        // Задача действительно выполняется в WorkManager
                        // Статус IN_PROGRESS в файле корректный, ничего не делаем
                    }
                    WorkManagerDataSource.WorkStateResult.NOT_FOUND -> {
                        // Задача не найдена в WorkManager и не в очереди
                        // Возможно, она была потеряна - добавляем обратно в очередь
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
        
        // Если получили ответ, уведомляем очередь о завершении
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
            // Удаляем из очереди, если задача там
            queueManager.removeFromQueue(requestId)
            // Отменяем в WorkManager, если задача там
            workManager.cancelRequest(requestId)
            // Уведомляем очередь о завершении
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
            // Удаляем из очереди
            queueManager.removeFromQueue(requestId)
            // Уведомляем очередь о завершении (на случай если задача была активна)
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
        
        // Получаем все задачи из файловой системы
        val allTaskIds = fileStorage.getAllTaskIds()
        
        for (requestId in allTaskIds) {
            // Проверяем, что статус в файле IN_PROGRESS (не завершена)
            val taskInfo = fileStorage.loadTaskInfo(requestId)
            if (taskInfo != null && taskInfo.status == RequestStatus.IN_PROGRESS) {
                // Проверяем, что нет ответа (задача еще не завершена)
                val response = fileStorage.loadTaskResponse(requestId)
                if (response == null || response.responseJson == null) {
                    // Добавляем задачу в список pending
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
        // Очищаем нашу очередь и WorkManager
        val queueCleared = queueManager.clearAll()
        workManager.cancelAllTasks()
        return queueCleared
    }
    
    /**
     * Получает статистику очереди
     */
    fun getQueueStats(): TaskQueueManager.QueueStats {
        return queueManager.getQueueStats()
    }
    
    /**
     * Устанавливает максимальное количество одновременных задач
     */
    suspend fun setMaxConcurrentTasks(count: Int) {
        queueManager.setMaxConcurrentTasks(count)
    }
    
    /**
     * Устанавливает максимальный размер очереди
     */
    fun setMaxQueueSize(size: Int) {
        queueManager.setMaxQueueSize(size)
    }
    
    /**
     * Синхронизирует состояние очереди
     */
    suspend fun syncQueueState() {
        queueManager.syncQueueState(fileStorage)
    }
    
    /**
     * Принудительно обрабатывает очередь
     */
    suspend fun processQueue() {
        queueManager.processQueue()
    }
}
