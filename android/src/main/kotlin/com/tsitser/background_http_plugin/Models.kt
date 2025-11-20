package com.tsitser.background_http_plugin

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Статусы выполнения HTTP запроса
 */
enum class RequestStatus {
    IN_PROGRESS,    // Запрос в процессе выполнения
    COMPLETED,      // Получен ответ от сервера
    FAILED          // Запрос завершился с ошибкой
}

/**
 * Модель для multipart файла
 */
@Serializable
data class MultipartFile(
    val filePath: String,
    val filename: String? = null,
    val contentType: String? = null
)

/**
 * Модель HTTP запроса
 */
@Serializable
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
    val stuckTimeoutBuffer: Int? = null, // Запас времени в секундах для определения зависших запросов в процессе выполнения (по умолчанию 60)
    val queueTimeout: Int? = null // Максимальное время ожидания в очереди в секундах (по умолчанию 600 = 10 минут)
)

/**
 * Модель HTTP ответа
 */
@Serializable
data class HttpResponse(
    val requestId: String,
    val statusCode: Int,
    val headers: Map<String, String>,
    val body: String? = null,
    val responseFilePath: String? = null,
    val status: RequestStatus,
    val error: String? = null
)

/**
 * Информация о запросе (ID и путь к файлу запроса)
 */
@Serializable
data class RequestInfo(
    val requestId: String,
    val requestFilePath: String
)

/**
 * Модель для хранения статуса запроса
 */
@Serializable
data class RequestStatusInfo(
    val requestId: String,
    val status: RequestStatus,
    val error: String? = null,
    val startTime: Long? = null // Время начала запроса в миллисекундах (для определения зависших запросов)
)

