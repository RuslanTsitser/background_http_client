package com.tsitser.background_http_plugin

import android.content.Context
import android.util.Log
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import java.util.UUID

/**
 * Менеджер для работы с файлами запросов и ответов
 */
object FileManager {
    private const val TAG = "FileManager"
    private const val REQUESTS_DIR = "background_http_requests"
    private const val RESPONSES_DIR = "background_http_responses"
    private const val STATUS_DIR = "background_http_status"

    /**
     * Получает директорию для сохранения файлов
     */
    fun getStorageDir(context: Context): File {
        val dir = File(context.filesDir, "background_http_client")
        if (!dir.exists()) {
            dir.mkdirs()
        }
        return dir
    }

    /**
     * Сохраняет запрос в файл и возвращает информацию о запросе
     * Если body указан, сохраняет его в отдельный файл для потоковой отправки
     */
    fun saveRequest(context: Context, request: HttpRequest): RequestInfo {
        // Используем кастомный ID, если указан, иначе генерируем автоматически
        val requestId = request.requestId ?: UUID.randomUUID().toString()
        val storageDir = getStorageDir(context)
        val requestsDir = File(storageDir, REQUESTS_DIR)
        if (!requestsDir.exists()) {
            requestsDir.mkdirs()
        }

        // Если body указан, сохраняем его в отдельный файл
        var bodyFilePath: String? = null
        if (request.body != null) {
            val bodyDir = File(storageDir, "request_bodies")
            if (!bodyDir.exists()) {
                bodyDir.mkdirs()
            }
            val bodyFile = File(bodyDir, "$requestId.body")
            bodyFile.writeText(request.body, Charsets.UTF_8)
            bodyFilePath = bodyFile.absolutePath
            Log.d(TAG, "Request body saved to file: $bodyFilePath")
        }

        // Создаем запрос без body (он в файле), но сохраняем путь к файлу
        val requestWithoutBody = request.copy(body = null)
        val requestFile = File(requestsDir, "$requestId.json")
        
        // Сохраняем JSON запроса
        val requestJson = Json.encodeToString(requestWithoutBody)
        requestFile.writeText(requestJson)
        
        // Сохраняем путь к файлу body в отдельном файле для удобства
        if (bodyFilePath != null) {
            val bodyPathFile = File(requestsDir, "$requestId.body_path")
            bodyPathFile.writeText(bodyFilePath)
        }

        Log.d(TAG, "Request saved: $requestId -> ${requestFile.absolutePath}")

        return RequestInfo(
            requestId = requestId,
            requestFilePath = requestFile.absolutePath
        )
    }
    
    /**
     * Получает путь к файлу с телом запроса
     */
    fun getBodyFilePath(context: Context, requestId: String): String? {
        val storageDir = getStorageDir(context)
        val requestsDir = File(storageDir, REQUESTS_DIR)
        val bodyPathFile = File(requestsDir, "$requestId.body_path")
        
        return if (bodyPathFile.exists()) {
            bodyPathFile.readText()
        } else {
            null
        }
    }

    /**
     * Получает файл запроса
     */
    fun getRequestFile(context: Context, requestId: String): File? {
        val storageDir = getStorageDir(context)
        val requestsDir = File(storageDir, REQUESTS_DIR)
        val requestFile = File(requestsDir, "$requestId.json")
        return if (requestFile.exists()) requestFile else null
    }

    /**
     * Загружает запрос из файла
     */
    fun loadRequest(context: Context, requestId: String): HttpRequest? {
        val requestFile = getRequestFile(context, requestId)
        return if (requestFile != null) {
            try {
                val json = requestFile.readText()
                Json.decodeFromString<HttpRequest>(json)
            } catch (e: Exception) {
                Log.e(TAG, "Error loading request $requestId", e)
                null
            }
        } else {
            null
        }
    }

    /**
     * Сохраняет ответ в файл
     */
    fun saveResponse(context: Context, response: HttpResponse) {
        val storageDir = getStorageDir(context)
        val responsesDir = File(storageDir, RESPONSES_DIR)
        if (!responsesDir.exists()) {
            responsesDir.mkdirs()
        }

        val responseFile = File(responsesDir, "${response.requestId}.json")
        val responseJson = Json.encodeToString(response)
        responseFile.writeText(responseJson)

        Log.d(TAG, "Response saved: ${response.requestId} -> ${responseFile.absolutePath}")
    }

    /**
     * Загружает ответ из файла
     */
    fun loadResponse(context: Context, requestId: String): HttpResponse? {
        val storageDir = getStorageDir(context)
        val responsesDir = File(storageDir, RESPONSES_DIR)
        val responseFile = File(responsesDir, "$requestId.json")

        return if (responseFile.exists()) {
            try {
                val json = responseFile.readText()
                Json.decodeFromString<HttpResponse>(json)
            } catch (e: Exception) {
                Log.e(TAG, "Error loading response $requestId", e)
                null
            }
        } else {
            null
        }
    }

    /**
     * Сохраняет статус запроса
     */
    fun saveStatus(context: Context, statusInfo: RequestStatusInfo) {
        val storageDir = getStorageDir(context)
        val statusDir = File(storageDir, STATUS_DIR)
        if (!statusDir.exists()) {
            statusDir.mkdirs()
        }

        val statusFile = File(statusDir, "${statusInfo.requestId}.json")
        val statusJson = Json.encodeToString(statusInfo)
        statusFile.writeText(statusJson)
    }

    /**
     * Загружает статус запроса
     */
    fun loadStatus(context: Context, requestId: String): RequestStatusInfo? {
        val storageDir = getStorageDir(context)
        val statusDir = File(storageDir, STATUS_DIR)
        val statusFile = File(statusDir, "$requestId.json")

        return if (statusFile.exists()) {
            try {
                val json = statusFile.readText()
                Json.decodeFromString<RequestStatusInfo>(json)
            } catch (e: Exception) {
                Log.e(TAG, "Error loading status $requestId", e)
                null
            }
        } else {
            null
        }
    }

    /**
     * Удаляет все файлы, связанные с запросом
     */
    fun deleteRequestFiles(context: Context, requestId: String) {
        val storageDir = getStorageDir(context)
        
        // Удаляем файл запроса
        val requestsDir = File(storageDir, REQUESTS_DIR)
        val requestFile = File(requestsDir, "$requestId.json")
        if (requestFile.exists()) {
            requestFile.delete()
            Log.d(TAG, "Deleted request file: ${requestFile.absolutePath}")
        }
        
        // Удаляем файл body_path
        val bodyPathFile = File(requestsDir, "$requestId.body_path")
        if (bodyPathFile.exists()) {
            bodyPathFile.delete()
            Log.d(TAG, "Deleted body path file: ${bodyPathFile.absolutePath}")
        }
        
        // Удаляем файл body (если существует)
        val bodyDir = File(storageDir, "request_bodies")
        val bodyFile = File(bodyDir, "$requestId.body")
        if (bodyFile.exists()) {
            bodyFile.delete()
            Log.d(TAG, "Deleted body file: ${bodyFile.absolutePath}")
        }
        
        // Удаляем файл ответа JSON
        val responsesDir = File(storageDir, RESPONSES_DIR)
        val responseJsonFile = File(responsesDir, "$requestId.json")
        if (responseJsonFile.exists()) {
            responseJsonFile.delete()
            Log.d(TAG, "Deleted response JSON file: ${responseJsonFile.absolutePath}")
        }
        
        // Удаляем файл ответа (данные)
        val responseDataFile = File(responsesDir, "${requestId}_response.txt")
        if (responseDataFile.exists()) {
            responseDataFile.delete()
            Log.d(TAG, "Deleted response data file: ${responseDataFile.absolutePath}")
        }
        
        // Удаляем файл статуса
        val statusDir = File(storageDir, STATUS_DIR)
        val statusFile = File(statusDir, "$requestId.json")
        if (statusFile.exists()) {
            statusFile.delete()
            Log.d(TAG, "Deleted status file: ${statusFile.absolutePath}")
        }
        
        Log.d(TAG, "All files deleted for request: $requestId")
    }
}

