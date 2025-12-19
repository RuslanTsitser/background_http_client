package com.tsitser.background_http_plugin.domain.repository

import com.tsitser.background_http_plugin.domain.entity.TaskInfo

/**
 * Repository for working with HTTP request tasks.
 */
interface TaskRepository {
    /**
     * Creates a new HTTP request task.
     * @return TaskInfo with information about the created task.
     */
    suspend fun createTask(request: com.tsitser.background_http_plugin.domain.entity.HttpRequest): TaskInfo

    /**
     * Gets task information by ID.
     * @return TaskInfo or null if the task is not found.
     */
    suspend fun getTaskInfo(requestId: String): TaskInfo?

    /**
     * Gets task response by ID.
     * @return TaskInfo with responseJson or null if the task is not found.
     */
    suspend fun getTaskResponse(requestId: String): TaskInfo?

    /**
     * Cancels a task by ID.
     * @return true if the task was cancelled, false if it failed, null if the task does not exist.
     */
    suspend fun cancelTask(requestId: String): Boolean?

    /**
     * Deletes a task and all related files by ID.
     * @return true if the task was deleted, false if it failed, null if the task does not exist.
     */
    suspend fun deleteTask(requestId: String): Boolean?

    /**
     * Gets a list of pending tasks with registration dates.
     * @return list of pending tasks.
     */
    suspend fun getPendingTasks(): List<PendingTask>

    /**
     * Cancels all tasks.
     * @return number of cancelled tasks.
     */
    suspend fun cancelAllTasks(): Int
}

/**
 * Information about a pending task.
 */
data class PendingTask(
    val requestId: String,
    val registrationDate: Long
)

