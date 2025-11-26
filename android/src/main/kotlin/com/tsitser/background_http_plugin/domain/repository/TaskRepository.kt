package com.tsitser.background_http_plugin.domain.repository

import com.tsitser.background_http_plugin.domain.entity.TaskInfo

/**
 * Репозиторий для работы с задачами HTTP запросов
 */
interface TaskRepository {
    /**
     * Создает новую задачу HTTP запроса
     * @return TaskInfo с информацией о созданной задаче
     */
    suspend fun createTask(request: com.tsitser.background_http_plugin.domain.entity.HttpRequest): TaskInfo

    /**
     * Получает информацию о задаче по ID
     * @return TaskInfo или null если задача не найдена
     */
    suspend fun getTaskInfo(requestId: String): TaskInfo?

    /**
     * Получает ответ задачи по ID
     * @return TaskInfo с responseJson или null если задача не найдена
     */
    suspend fun getTaskResponse(requestId: String): TaskInfo?

    /**
     * Отменяет задачу по ID
     * @return true если задача отменена, false если не получилось, null если задачи не существует
     */
    suspend fun cancelTask(requestId: String): Boolean?

    /**
     * Удаляет задачу и все связанные файлы по ID
     * @return true если задача удалена, false если не получилось, null если задачи не существует
     */
    suspend fun deleteTask(requestId: String): Boolean?

    /**
     * Получает список задач в ожидании с датами регистрации
     * @return список задач в ожидании
     */
    suspend fun getPendingTasks(): List<PendingTask>

    /**
     * Отменяет все задачи
     * @return количество отмененных задач
     */
    suspend fun cancelAllTasks(): Int
}

/**
 * Информация о задаче в ожидании
 */
data class PendingTask(
    val requestId: String,
    val registrationDate: Long
)

