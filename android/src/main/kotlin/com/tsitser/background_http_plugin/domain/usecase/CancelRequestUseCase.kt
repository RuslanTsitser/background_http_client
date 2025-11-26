package com.tsitser.background_http_plugin.domain.usecase

import com.tsitser.background_http_plugin.domain.repository.TaskRepository

/**
 * Use case для отмены задачи
 */
class CancelRequestUseCase(
    private val repository: TaskRepository
) {
    suspend operator fun invoke(requestId: String): Boolean? {
        return repository.cancelTask(requestId)
    }
}

