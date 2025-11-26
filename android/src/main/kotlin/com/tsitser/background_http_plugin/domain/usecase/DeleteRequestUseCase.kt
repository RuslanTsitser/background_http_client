package com.tsitser.background_http_plugin.domain.usecase

import com.tsitser.background_http_plugin.domain.repository.TaskRepository

/**
 * Use case для удаления задачи
 */
class DeleteRequestUseCase(
    private val repository: TaskRepository
) {
    suspend operator fun invoke(requestId: String): Boolean? {
        return repository.deleteTask(requestId)
    }
}

