package com.tsitser.background_http_plugin.domain.entity

/**
 * HTTP request model
 */
data class HttpRequest(
    val url: String,
    val method: String,
    val headers: Map<String, String>? = null,
    val body: String? = null,
    val queryParameters: Map<String, String>? = null,
    val timeout: Int? = null,
    val multipartFields: Map<String, String>? = null,
    val multipartFiles: Map<String, MultipartFile>? = null,
    val requestId: String? = null,
    val retries: Int? = null,
    val stuckTimeoutBuffer: Int? = null,
    val queueTimeout: Int? = null
)

/**
 * Multipart file model
 */
data class MultipartFile(
    val filePath: String,
    val filename: String? = null,
    val contentType: String? = null
)

