package com.tsitser.background_http_plugin.domain.entity

/**
 * Информация о задаче в нативном HTTP сервисе
 */
data class TaskInfo(
    val id: String,
    val status: RequestStatus,
    val path: String,
    val registrationDate: Long, // timestamp в миллисекундах
    val responseJson: Map<String, Any>? = null
)

