package com.tsitser.background_http_plugin.domain.usecase

import com.tsitser.background_http_plugin.domain.entity.HttpRequest
import com.tsitser.background_http_plugin.domain.entity.TaskInfo
import com.tsitser.background_http_plugin.domain.repository.TaskRepository

/**
 * Use case for creating HTTP request
 */
class CreateRequestUseCase(
    private val repository: TaskRepository
) {
    suspend operator fun invoke(request: HttpRequest): TaskInfo {
        return repository.createTask(request)
    }
}

