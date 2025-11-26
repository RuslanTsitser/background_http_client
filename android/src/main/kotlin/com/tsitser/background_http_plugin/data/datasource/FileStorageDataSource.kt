package com.tsitser.background_http_plugin.data.datasource

import android.content.Context
import com.tsitser.background_http_plugin.domain.entity.HttpRequest
import com.tsitser.background_http_plugin.domain.entity.RequestStatus
import com.tsitser.background_http_plugin.domain.entity.TaskInfo
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Data source для работы с файловым хранилищем
 */
class FileStorageDataSource(private val context: Context) {

    private val storageDir: File by lazy {
        File(context.filesDir, "background_http_client").apply {
            if (!exists()) mkdirs()
        }
    }

    private val requestsDir: File by lazy {
        File(storageDir, "requests").apply {
            if (!exists()) mkdirs()
        }
    }

    private val responsesDir: File by lazy {
        File(storageDir, "responses").apply {
            if (!exists()) mkdirs()
        }
    }

    private val statusDir: File by lazy {
        File(storageDir, "status").apply {
            if (!exists()) mkdirs()
        }
    }

    private val bodiesDir: File by lazy {
        File(storageDir, "request_bodies").apply {
            if (!exists()) mkdirs()
        }
    }

    /**
     * Сохраняет запрос в файл и возвращает информацию о задаче
     */
    fun saveRequest(request: HttpRequest, requestId: String, registrationDate: Long): TaskInfo {
        // Сохраняем body в отдельный файл, если он есть
        if (request.body != null) {
            val bodyFile = File(bodiesDir, "$requestId.body")
            bodyFile.writeText(request.body)
        }

        // Сохраняем запрос в JSON
        val requestFile = File(requestsDir, "$requestId.json")
        val requestJson = JSONObject().apply {
            put("url", request.url)
            put("method", request.method)
            put("headers", request.headers?.let { JSONObject(it as Map<*, *>) } ?: JSONObject())
            put("body", request.body ?: "")
            put("queryParameters", request.queryParameters?.let { JSONObject(it as Map<*, *>) } ?: JSONObject())
            put("timeout", request.timeout ?: 120)
            put("multipartFields", request.multipartFields?.let { JSONObject(it as Map<*, *>) } ?: JSONObject())
            put("multipartFiles", request.multipartFiles?.let { files ->
                JSONObject().apply {
                    files.forEach { (key, file) ->
                        put(key, JSONObject().apply {
                            put("filePath", file.filePath)
                            put("filename", file.filename ?: "")
                            put("contentType", file.contentType ?: "")
                        })
                    }
                }
            } ?: JSONObject())
            put("requestId", requestId)
            put("retries", request.retries ?: 0)
            put("stuckTimeoutBuffer", request.stuckTimeoutBuffer ?: 60)
            put("queueTimeout", request.queueTimeout ?: 600)
        }
        requestFile.writeText(requestJson.toString())

        // Сохраняем начальный статус
        saveStatus(requestId, RequestStatus.IN_PROGRESS, registrationDate)

        return TaskInfo(
            id = requestId,
            status = RequestStatus.IN_PROGRESS,
            path = requestFile.absolutePath,
            registrationDate = registrationDate
        )
    }

    /**
     * Загружает информацию о задаче
     */
    fun loadTaskInfo(requestId: String): TaskInfo? {
        val requestFile = File(requestsDir, "$requestId.json")
        if (!requestFile.exists()) {
            return null
        }

        val status = loadStatus(requestId) ?: RequestStatus.IN_PROGRESS
        // Получаем дату регистрации из файла статуса, если она там есть, иначе используем lastModified
        val registrationDate = loadRegistrationDate(requestId) ?: requestFile.lastModified()

        return TaskInfo(
            id = requestId,
            status = status,
            path = requestFile.absolutePath,
            registrationDate = registrationDate
        )
    }

    /**
     * Загружает дату регистрации из файла статуса
     */
    private fun loadRegistrationDate(requestId: String): Long? {
        val statusFile = File(statusDir, "$requestId.json")
        if (!statusFile.exists()) {
            return null
        }

        return try {
            val jsonString = statusFile.readText()
            val json = JSONObject(jsonString)
            if (json.has("startTime")) {
                json.getLong("startTime")
            } else {
                null
            }
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Загружает ответ задачи
     */
    fun loadTaskResponse(requestId: String): TaskInfo? {
        val taskInfo = loadTaskInfo(requestId) ?: return null

        val responseFile = File(responsesDir, "$requestId.json")
        if (!responseFile.exists()) {
            return taskInfo
        }

        val responseJson = try {
            val jsonString = responseFile.readText()
            val json = JSONObject(jsonString)
            json.toMap()
        } catch (e: Exception) {
            null
        }

        return taskInfo.copy(responseJson = responseJson)
    }

    /**
     * Сохраняет статус задачи
     */
    fun saveStatus(requestId: String, status: RequestStatus, startTime: Long? = null) {
        val statusFile = File(statusDir, "$requestId.json")
        val statusJson = JSONObject().apply {
            put("requestId", requestId)
            put("status", status.value)
            if (startTime != null) {
                put("startTime", startTime)
            }
        }
        statusFile.writeText(statusJson.toString())
    }

    /**
     * Загружает статус задачи
     */
    fun loadStatus(requestId: String): RequestStatus? {
        val statusFile = File(statusDir, "$requestId.json")
        if (!statusFile.exists()) {
            return null
        }

        return try {
            val jsonString = statusFile.readText()
            val json = JSONObject(jsonString)
            val statusValue = json.getInt("status")
            enumValues<RequestStatus>().firstOrNull { it.value == statusValue }
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Сохраняет ответ от сервера
     */
    fun saveResponse(
        requestId: String,
        statusCode: Int,
        headers: Map<String, String>,
        body: String?,
        responseFilePath: String?,
        status: RequestStatus,
        error: String?
    ) {
        val responseFile = File(responsesDir, "$requestId.json")
        val responseJson = JSONObject().apply {
            put("requestId", requestId)
            put("statusCode", statusCode)
            put("headers", JSONObject(headers as Map<*, *>))
            put("body", body ?: "")
            put("responseFilePath", responseFilePath ?: "")
            put("status", status.value)
            put("error", error ?: "")
        }
        responseFile.writeText(responseJson.toString())

        // Обновляем статус
        saveStatus(requestId, status)
    }

    /**
     * Удаляет все файлы, связанные с задачей
     */
    fun deleteTaskFiles(requestId: String): Boolean {
        var deleted = true

        // Удаляем файл запроса
        File(requestsDir, "$requestId.json").takeIf { it.exists() }?.delete() ?: run { deleted = false }

        // Удаляем файл body
        File(bodiesDir, "$requestId.body").takeIf { it.exists() }?.delete()

        // Удаляем файл ответа JSON
        File(responsesDir, "$requestId.json").takeIf { it.exists() }?.delete()

        // Удаляем файл ответа (данные)
        File(responsesDir, "${requestId}_response.txt").takeIf { it.exists() }?.delete()

        // Удаляем файл статуса
        File(statusDir, "$requestId.json").takeIf { it.exists() }?.delete()

        return deleted
    }

    /**
     * Проверяет существование задачи
     */
    fun taskExists(requestId: String): Boolean {
        return File(requestsDir, "$requestId.json").exists()
    }

    /**
     * Получает список всех ID задач из файловой системы
     */
    fun getAllTaskIds(): List<String> {
        return requestsDir.listFiles()
            ?.filter { it.isFile && it.name.endsWith(".json") }
            ?.map { it.name.removeSuffix(".json") }
            ?: emptyList()
    }

    /**
     * Вспомогательная функция для преобразования JSONObject в Map
     */
    private fun JSONObject.toMap(): Map<String, Any> {
        val map = mutableMapOf<String, Any>()
        val keys = this.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val value = this.get(key)
            map[key] = when (value) {
                is JSONObject -> value.toMap()
                is JSONArray -> value.toList()
                else -> value
            }
        }
        return map
    }

    private fun JSONArray.toList(): List<Any> {
        val list = mutableListOf<Any>()
        for (i in 0 until this.length()) {
            val value = this.get(i)
            list.add(
                when (value) {
                    is JSONObject -> value.toMap()
                    is JSONArray -> value.toList()
                    else -> value
                }
            )
        }
        return list
    }
}

