package com.tsitser.background_http_plugin.domain.usecase

import com.tsitser.background_http_plugin.domain.entity.TaskInfo
import com.tsitser.background_http_plugin.domain.repository.TaskRepository

/**
 * Use case for getting task response
 */
class GetResponseUseCase(
    private val repository: TaskRepository
) {
    suspend operator fun invoke(requestId: String): TaskInfo? {
        return repository.getTaskResponse(requestId)
    }
}

