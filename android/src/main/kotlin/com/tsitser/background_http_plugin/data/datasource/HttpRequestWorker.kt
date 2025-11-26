package com.tsitser.background_http_plugin.data.datasource

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.tsitser.background_http_plugin.domain.entity.RequestStatus
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.*
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * Worker для выполнения HTTP запросов в фоне
 */
class HttpRequestWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    private val fileStorage = FileStorageDataSource(context)

    companion object {
        const val KEY_REQUEST_ID = "request_id"
        private const val TAG = "HttpRequestWorker"
    }

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val requestId = inputData.getString(KEY_REQUEST_ID)
            ?: return@withContext Result.failure()

        try {
            val taskInfo = fileStorage.loadTaskInfo(requestId)
                ?: return@withContext Result.failure()

            // Загружаем запрос из файла
            val requestFile = File(taskInfo.path)
            if (!requestFile.exists()) {
                Log.e(TAG, "Request file not found: ${taskInfo.path}")
                return@withContext Result.failure()
            }

            val requestJson = org.json.JSONObject(requestFile.readText())
            val url = requestJson.getString("url")
            val method = requestJson.getString("method")
            val headers = requestJson.optJSONObject("headers")?.toMap() as? Map<String, String>
            val body = requestJson.optString("body").takeIf { it.isNotEmpty() }
            val queryParameters = requestJson.optJSONObject("queryParameters")?.toMap() as? Map<String, String>
            val timeout = requestJson.optInt("timeout", 120)
            
            // Парсим multipartFields
            val multipartFields = requestJson.optJSONObject("multipartFields")?.let { json ->
                val map = mutableMapOf<String, String>()
                json.keys().forEach { key ->
                    val value = json.optString(key, "")
                    if (value.isNotEmpty()) {
                        map[key] = value
                    }
                }
                map.takeIf { it.isNotEmpty() }
            }
            
            // Парсим multipartFiles
            val multipartFiles = requestJson.optJSONObject("multipartFiles")?.let { json ->
                val map = mutableMapOf<String, Map<String, Any>>()
                json.keys().forEach { key ->
                    val fileObj = json.optJSONObject(key)
                    if (fileObj != null) {
                        val fileMap = mutableMapOf<String, Any>()
                        fileMap["filePath"] = fileObj.optString("filePath", "")
                        fileMap["filename"] = fileObj.optString("filename", "")
                        fileMap["contentType"] = fileObj.optString("contentType", "")
                        map[key] = fileMap
                    }
                }
                map.takeIf { it.isNotEmpty() }
            }
            
            val retries = requestJson.optInt("retries", 0)

            // Строим URL с query параметрами
            var requestUrl = url
            if (!queryParameters.isNullOrEmpty()) {
                val urlBuilder = url.toHttpUrlOrNull()?.newBuilder()
                queryParameters.forEach { (key, value) ->
                    urlBuilder?.addQueryParameter(key, value)
                }
                requestUrl = urlBuilder?.build()?.toString() ?: url
            }

            // Создаем OkHttp клиент
            val client = OkHttpClient.Builder()
                .connectTimeout(timeout.toLong(), TimeUnit.SECONDS)
                .readTimeout(timeout.toLong(), TimeUnit.SECONDS)
                .writeTimeout(timeout.toLong(), TimeUnit.SECONDS)
                .build()

            // Создаем request body
            val requestBody = when {
                !multipartFields.isNullOrEmpty() || !multipartFiles.isNullOrEmpty() -> {
                    buildMultipartBody(multipartFields, multipartFiles)
                }
                body != null && method != "GET" && method != "HEAD" -> {
                    body.toRequestBody("application/json".toMediaType())
                }
                else -> null
            }

            // Создаем запрос
            val requestBuilder = okhttp3.Request.Builder()
                .url(requestUrl)
                .method(method, requestBody)

            // Добавляем заголовки (но не Content-Type для multipart, OkHttp установит его автоматически)
            headers?.forEach { (key, value) ->
                if (requestBody == null || key.lowercase() != "content-type") {
                    requestBuilder.addHeader(key, value)
                }
            }

            // Выполняем запрос
            val response = client.newCall(requestBuilder.build()).execute()

            // Обрабатываем ответ
            val responseBody = response.body?.string()
            val responseHeaders = response.headers.toMultimap().mapValues { it.value.firstOrNull() ?: "" }
            val statusCode = response.code

            val status = if (statusCode in 200..299) {
                RequestStatus.COMPLETED
            } else {
                RequestStatus.FAILED
            }

            // Сохраняем ответ
            val responseFilePath = responseBody?.let { saveResponseBody(requestId, it) }
            fileStorage.saveResponse(
                requestId = requestId,
                statusCode = statusCode,
                headers = responseHeaders,
                body = responseBody?.takeIf { it.length <= 10000 }, // Сохраняем только маленькие ответы в body
                responseFilePath = responseFilePath,
                status = status,
                error = if (status == RequestStatus.FAILED) responseBody ?: "Request failed" else null
            )

            Result.success()
        } catch (e: CancellationException) {
            // Отмена задачи - это нормальное поведение, не ошибка
            // Пробрасываем исключение дальше, чтобы WorkManager правильно обработал отмену
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "Error executing request $requestId", e)
            fileStorage.saveStatus(requestId, RequestStatus.FAILED)
            fileStorage.saveResponse(
                requestId = requestId,
                statusCode = 0,
                headers = emptyMap(),
                body = null,
                responseFilePath = null,
                status = RequestStatus.FAILED,
                error = e.message ?: "Unknown error"
            )
            Result.retry() // WorkManager автоматически повторит при сетевых ошибках
        }
    }

    private fun buildMultipartBody(
        fields: Map<String, String>?,
        files: Map<String, Map<String, Any>>?
    ): RequestBody {
        return MultipartBody.Builder()
            .setType(MultipartBody.FORM)
            .apply {
                fields?.forEach { (key, value) ->
                    addFormDataPart(key, value)
                }
                files?.forEach { (fieldName, fileInfo) ->
                    val filePath = fileInfo["filePath"] as? String
                    val filename = fileInfo["filename"] as? String
                    val contentType = fileInfo["contentType"] as? String

                    if (filePath != null) {
                        val file = File(filePath)
                        if (file.exists()) {
                            val fileMediaType = (contentType?.takeIf { it.isNotEmpty() }?.toMediaType()
                                ?: "application/octet-stream".toMediaType())
                            val finalFilename = filename?.takeIf { it.isNotEmpty() } ?: file.name
                            addFormDataPart(
                                fieldName,
                                finalFilename,
                                file.asRequestBody(fileMediaType)
                            )
                        } else {
                            Log.e(TAG, "File not found: $filePath")
                        }
                    } else {
                        Log.e(TAG, "File path is null for field: $fieldName")
                    }
                }
            }
            .build()
    }

    private fun saveResponseBody(requestId: String, body: String): String {
        val responsesDir = File(applicationContext.filesDir, "background_http_client/responses")
        if (!responsesDir.exists()) {
            responsesDir.mkdirs()
        }
        val responseFile = File(responsesDir, "${requestId}_response.txt")
        responseFile.writeText(body)
        return responseFile.absolutePath
    }

    private fun org.json.JSONObject.toMap(): Map<String, Any> {
        val map = mutableMapOf<String, Any>()
        val keys = this.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val value = this.get(key)
            map[key] = when (value) {
                is org.json.JSONObject -> value.toMap()
                is org.json.JSONArray -> value.toList()
                else -> value
            }
        }
        return map
    }

    private fun org.json.JSONArray.toList(): List<Any> {
        val list = mutableListOf<Any>()
        for (i in 0 until this.length()) {
            val value = this.get(i)
            list.add(
                when (value) {
                    is org.json.JSONObject -> value.toMap()
                    is org.json.JSONArray -> value.toList()
                    else -> value
                }
            )
        }
        return list
    }
}

