package com.tsitser.background_http_plugin.domain.entity

/**
 * Статусы выполнения HTTP запроса
 */
enum class RequestStatus(val value: Int) {
    IN_PROGRESS(0),
    COMPLETED(1),
    FAILED(2)
}

