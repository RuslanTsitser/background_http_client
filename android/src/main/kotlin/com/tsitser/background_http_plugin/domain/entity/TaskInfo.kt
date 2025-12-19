package com.tsitser.background_http_plugin.domain.entity

/**
 * Task information in native HTTP service
 */
data class TaskInfo(
    val id: String,
    val status: RequestStatus,
    val path: String,
    val registrationDate: Long, // timestamp in milliseconds
    val responseJson: Map<String, Any>? = null
)

