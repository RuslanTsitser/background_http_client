package com.tsitser.background_http_plugin

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.Data
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.util.concurrent.TimeUnit
import java.io.InputStreamReader
import kotlin.math.min
import java.net.ConnectException
import java.net.HttpURLConnection
import java.net.SocketException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.net.URL
import java.net.URLEncoder
import java.util.UUID

/**
 * Worker для выполнения HTTP запросов в фоновом режиме
 */
class HttpRequestWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    companion object {
        const val TAG = "HttpRequestWorker"
        const val KEY_REQUEST_ID = "request_id"
        const val KEY_RETRIES_REMAINING = "retries_remaining"
    }

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        try {
            val requestId = inputData.getString(KEY_REQUEST_ID)
                ?: return@withContext Result.failure()

            val retriesRemaining = inputData.getInt(KEY_RETRIES_REMAINING, -1)
            
            Log.d(TAG, "Starting HTTP request: $requestId (retries remaining: $retriesRemaining)")

            // Загружаем запрос из файла
            val request = FileManager.loadRequest(applicationContext, requestId)
                ?: return@withContext Result.failure()

            // Обновляем статус на "в процессе"
            FileManager.saveStatus(
                applicationContext,
                RequestStatusInfo(requestId, RequestStatus.IN_PROGRESS)
            )

            // Выполняем HTTP запрос (одна попытка)
            val response = executeHttpRequest(request, requestId)

            // Проверяем, нужна ли повторная попытка
            val maxRetries = (request.retries ?: 0).coerceIn(0, 10)
            val currentRetriesRemaining = if (retriesRemaining >= 0) retriesRemaining else maxRetries
            
            if (response.status == RequestStatus.FAILED && currentRetriesRemaining > 0) {
                // Нужна повторная попытка - планируем новый WorkRequest с задержкой
                // НЕ сохраняем ответ при промежуточных попытках, чтобы не перезаписывать файл
                val attempt = maxRetries - currentRetriesRemaining + 1
                val waitSeconds = minOf(2 shl minOf(attempt - 1, 8), 512).toLong()
                
                Log.d(TAG, "Request $requestId failed, scheduling retry in $waitSeconds seconds. ${currentRetriesRemaining - 1} retries remaining")
                
                // Обновляем статус на "ожидание повтора"
                FileManager.saveStatus(
                    applicationContext,
                    RequestStatusInfo(
                        requestId,
                        RequestStatus.IN_PROGRESS,
                        "Retrying in $waitSeconds seconds... (${currentRetriesRemaining - 1} retries remaining)"
                    )
                )
                
                // Планируем новый WorkRequest с задержкой через WorkManager
                // Это гарантирует работу даже при закрытом приложении
                val retryWorkRequest = OneTimeWorkRequestBuilder<HttpRequestWorker>()
                    .setInitialDelay(waitSeconds, TimeUnit.SECONDS)
                    .setConstraints(
                        androidx.work.Constraints.Builder()
                            .setRequiredNetworkType(androidx.work.NetworkType.CONNECTED)
                            .build()
                    )
                    .setInputData(
                        Data.Builder()
                            .putString(KEY_REQUEST_ID, requestId)
                            .putInt(KEY_RETRIES_REMAINING, currentRetriesRemaining - 1)
                            .build()
                    )
                    .addTag("request_${requestId}_retry")
                    .build()
                
                WorkManager.getInstance(applicationContext).enqueue(retryWorkRequest)
                
                // Возвращаем retry, чтобы WorkManager знал, что задача продолжается
                return@withContext Result.retry()
            }
            
            // Сохраняем ответ только при финальном результате (когда нет retries или все retries исчерпаны)
            FileManager.saveResponse(applicationContext, response)

            // Обновляем статус
            FileManager.saveStatus(
                applicationContext,
                RequestStatusInfo(
                    requestId,
                    response.status,
                    response.error
                )
            )

            Log.d(TAG, "HTTP request completed: $requestId, status: ${response.status}")

            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Error executing HTTP request", e)
            val requestId = inputData.getString(KEY_REQUEST_ID)
            val retriesRemaining = inputData.getInt(KEY_RETRIES_REMAINING, -1)
            
            // Проверяем, является ли это сетевой ошибкой
            val isNetworkError = e is SocketException || 
                                e is ConnectException || 
                                e is UnknownHostException || 
                                e is SocketTimeoutException ||
                                (e.message?.contains("Network is unreachable", ignoreCase = true) == true) ||
                                (e.message?.contains("Unable to resolve host", ignoreCase = true) == true)
            
            if (requestId != null) {
                if (isNetworkError) {
                    // При сетевой ошибке создаем новую задачу с NetworkType.CONNECTED constraint
                    // WorkManager автоматически выполнит задачу при появлении сети
                    Log.d(TAG, "Network error detected for request $requestId, scheduling retry when network is available")
                    
                    FileManager.saveStatus(
                        applicationContext,
                        RequestStatusInfo(
                            requestId,
                            RequestStatus.IN_PROGRESS,
                            "Waiting for network connection... (${e.message ?: "Network unavailable"})"
                        )
                    )
                    
                    // Создаем новую задачу с NetworkType.CONNECTED - WorkManager автоматически выполнит её при появлении сети
                    val networkWaitWorkRequest = OneTimeWorkRequestBuilder<HttpRequestWorker>()
                        .setConstraints(
                            androidx.work.Constraints.Builder()
                                .setRequiredNetworkType(androidx.work.NetworkType.CONNECTED)
                                .build()
                        )
                        .setInputData(
                            Data.Builder()
                                .putString(KEY_REQUEST_ID, requestId)
                                .putInt(KEY_RETRIES_REMAINING, retriesRemaining)
                                .build()
                        )
                        .addTag("request_${requestId}_network_wait")
                        .build()
                    
                    WorkManager.getInstance(applicationContext).enqueue(networkWaitWorkRequest)
                    
                    // Возвращаем success, так как мы создали новую задачу, которая будет ждать сеть
                    return@withContext Result.success()
                } else {
                    // Для других ошибок проверяем, есть ли еще попытки
                    val request = FileManager.loadRequest(applicationContext, requestId)
                    val maxRetries = (request?.retries ?: 0).coerceIn(0, 10)
                    val currentRetriesRemaining = if (retriesRemaining >= 0) retriesRemaining else maxRetries
                    
                    if (currentRetriesRemaining > 0) {
                        // Есть попытки - планируем повтор через WorkManager
                        val attempt = maxRetries - currentRetriesRemaining + 1
                        val waitSeconds = minOf(2 shl minOf(attempt - 1, 8), 512).toLong()
                        
                        Log.d(TAG, "Request $requestId error: ${e.message}, scheduling retry in $waitSeconds seconds. ${currentRetriesRemaining - 1} retries remaining")
                        
                        FileManager.saveStatus(
                            applicationContext,
                            RequestStatusInfo(
                                requestId,
                                RequestStatus.IN_PROGRESS,
                                "Retrying in $waitSeconds seconds... (${currentRetriesRemaining - 1} retries remaining)"
                            )
                        )
                        
                        val retryWorkRequest = OneTimeWorkRequestBuilder<HttpRequestWorker>()
                            .setInitialDelay(waitSeconds, TimeUnit.SECONDS)
                            .setConstraints(
                                androidx.work.Constraints.Builder()
                                    .setRequiredNetworkType(androidx.work.NetworkType.CONNECTED)
                                    .build()
                            )
                            .setInputData(
                                Data.Builder()
                                    .putString(KEY_REQUEST_ID, requestId)
                                    .putInt(KEY_RETRIES_REMAINING, currentRetriesRemaining - 1)
                                    .build()
                            )
                            .addTag("request_${requestId}_retry")
                            .build()
                        
                        WorkManager.getInstance(applicationContext).enqueue(retryWorkRequest)
                        return@withContext Result.retry()
                    } else {
                        // Попытки закончились
                        FileManager.saveStatus(
                            applicationContext,
                            RequestStatusInfo(
                                requestId,
                                RequestStatus.FAILED,
                                e.message ?: "Unknown error"
                            )
                        )
                        return@withContext Result.failure()
                    }
                }
            }
            Result.failure()
        }
    }

    /**
     * Выполняет HTTP запрос (одна попытка)
     */
    private suspend fun executeHttpRequest(
        request: HttpRequest,
        requestId: String
    ): HttpResponse = withContext(Dispatchers.IO) {
        val url = buildUrl(request.url, request.queryParameters)
        val connection = URL(url).openConnection() as HttpURLConnection

        try {
            // Настройка соединения
            connection.requestMethod = request.method
            // timeout приходит в секундах из Dart, но HttpURLConnection ожидает миллисекунды
            connection.connectTimeout = (request.timeout ?: 30) * 1000
            connection.readTimeout = (request.timeout ?: 30) * 1000

            // Проверяем, является ли это multipart запросом
            val isMultipart = request.multipartFields != null || request.multipartFiles != null

            // Установка заголовков
            request.headers?.forEach { (key, value) ->
                connection.setRequestProperty(key, value)
            }

            // Отправка тела запроса (для POST, PUT, PATCH)
            if (request.method in listOf("POST", "PUT", "PATCH")) {
                // Проверяем, сохранен ли body в файл
                val bodyFilePath = FileManager.getBodyFilePath(applicationContext, requestId)
                val hasBody = bodyFilePath != null || request.body != null
                
                if (isMultipart) {
                    // Multipart запрос
                    connection.doOutput = true
                    val boundary = "----WebKitFormBoundary${System.currentTimeMillis()}"
                    connection.setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
                    
                    connection.outputStream.use { output ->
                        writeMultipartBody(output, request, boundary)
                    }
                } else if (hasBody) {
                    // Обычный запрос с телом
                    connection.doOutput = true
                    
                    // Устанавливаем Content-Length и Content-Type ДО записи в outputStream
                    if (bodyFilePath != null) {
                        val bodyFile = java.io.File(bodyFilePath)
                        if (bodyFile.exists()) {
                            val bodySize = bodyFile.length()
                            connection.setRequestProperty("Content-Length", bodySize.toString())
                            if (connection.getRequestProperty("Content-Type") == null) {
                                connection.setRequestProperty("Content-Type", "application/json")
                            }
                            
                            connection.outputStream.use { output ->
                                bodyFile.inputStream().use { input ->
                                    input.copyTo(output)
                                }
                            }
                            Log.d(TAG, "Body sent from file: $bodyFilePath, size: $bodySize")
                        } else {
                            Log.e(TAG, "Body file not found: $bodyFilePath")
                        }
                    } else if (request.body != null) {
                        // Для обратной совместимости (если body не был сохранен в файл)
                        val bodyBytes = request.body.toByteArray(Charsets.UTF_8)
                        connection.setRequestProperty("Content-Length", bodyBytes.size.toString())
                        if (connection.getRequestProperty("Content-Type") == null) {
                            connection.setRequestProperty("Content-Type", "application/json")
                        }
                        
                        connection.outputStream.use { output ->
                            output.write(bodyBytes)
                        }
                    }
                }
            }

            // Выполнение запроса
            val responseCode = connection.responseCode

            // Чтение ответа
            val responseHeaders = connection.headerFields
                .filterKeys { it != null }
                .mapKeys { it.key!! }
                .mapValues { it.value.joinToString(", ") }

            val inputStream = if (responseCode >= 200 && responseCode < 300) {
                connection.inputStream
            } else {
                connection.errorStream
            }

            // Сохраняем ответ в файл как байты (без форматирования)
            // Примечание: файл будет перезаписан при каждой попытке, но сохраняется в JSON только при финальном результате
            val contentLength = connection.contentLength.toLong()
            val responseFilePath: String? = if (inputStream != null) {
                // Записываем байты напрямую в файл
                streamResponseToFile(applicationContext, requestId, inputStream, contentLength)
            } else {
                null
            }
            
            // Для маленьких ответов (<10KB) также сохраняем в body для удобства (опционально)
            val responseBody: String? = if (responseFilePath != null && contentLength > 0 && contentLength <= 10000) {
                try {
                    // Читаем файл как UTF-8 для body (только для текстовых ответов)
                    // Если это не UTF-8, body будет null
                    java.io.File(responseFilePath).readText(Charsets.UTF_8)
                } catch (e: Exception) {
                    // Если не удалось прочитать как UTF-8 (бинарные данные), оставляем null
                    null
                }
            } else {
                null
            }

            HttpResponse(
                requestId = requestId,
                statusCode = responseCode,
                headers = responseHeaders,
                // Для маленьких ответов (<10KB) также сохраняем в body для удобства
                body = responseBody,
                responseFilePath = responseFilePath,
                status = if (responseCode >= 200 && responseCode < 300) {
                    RequestStatus.COMPLETED
                } else {
                    RequestStatus.FAILED
                },
                error = if (responseCode >= 200 && responseCode < 300) null else responseBody
            )
        } finally {
            connection.disconnect()
        }
    }

    /**
     * Строит URL с query параметрами
     */
    private fun buildUrl(baseUrl: String, queryParameters: Map<String, String>?): String {
        if (queryParameters.isNullOrEmpty()) {
            return baseUrl
        }

        val urlBuilder = StringBuilder(baseUrl)
        if (!baseUrl.contains("?")) {
            urlBuilder.append("?")
        } else {
            urlBuilder.append("&")
        }

        queryParameters.forEach { (key, value) ->
            urlBuilder.append(URLEncoder.encode(key, Charsets.UTF_8.name()))
            urlBuilder.append("=")
            urlBuilder.append(URLEncoder.encode(value, Charsets.UTF_8.name()))
            urlBuilder.append("&")
        }

        // Удаляем последний &
        if (urlBuilder.endsWith("&")) {
            urlBuilder.setLength(urlBuilder.length - 1)
        }

        return urlBuilder.toString()
    }

    /**
     * Записывает multipart тело запроса
     */
    private fun writeMultipartBody(
        output: java.io.OutputStream,
        request: HttpRequest,
        boundary: String
    ) {
        val lineFeed = "\r\n"
        val boundaryLine = "--$boundary$lineFeed"
        val boundaryEnd = "--$boundary--$lineFeed"

        // Записываем поля
        request.multipartFields?.forEach { (key, value) ->
            output.write(boundaryLine.toByteArray(Charsets.UTF_8))
            output.write("Content-Disposition: form-data; name=\"$key\"$lineFeed".toByteArray(Charsets.UTF_8))
            output.write(lineFeed.toByteArray(Charsets.UTF_8))
            output.write(value.toByteArray(Charsets.UTF_8))
            output.write(lineFeed.toByteArray(Charsets.UTF_8))
        }

        // Записываем файлы
        request.multipartFiles?.forEach { (fieldName, multipartFile) ->
            val file = java.io.File(multipartFile.filePath)
            if (!file.exists()) {
                Log.w(TAG, "File not found: ${multipartFile.filePath}")
                return@forEach
            }

            val filename = multipartFile.filename ?: file.name
            val contentType = multipartFile.contentType
                ?: java.net.URLConnection.guessContentTypeFromName(file.name)
                ?: "application/octet-stream"

            output.write(boundaryLine.toByteArray(Charsets.UTF_8))
            output.write("Content-Disposition: form-data; name=\"$fieldName\"; filename=\"$filename\"$lineFeed".toByteArray(Charsets.UTF_8))
            output.write("Content-Type: $contentType$lineFeed".toByteArray(Charsets.UTF_8))
            output.write(lineFeed.toByteArray(Charsets.UTF_8))

            // Записываем содержимое файла
            file.inputStream().use { fileInput ->
                fileInput.copyTo(output)
            }

            output.write(lineFeed.toByteArray(Charsets.UTF_8))
        }

        // Завершающий boundary
        output.write(boundaryEnd.toByteArray(Charsets.UTF_8))
    }

    /**
     * Сохраняет ответ в файл как байты (без форматирования)
     * Записывает данные напрямую из InputStream в файл
     */
    private fun streamResponseToFile(
        context: Context,
        requestId: String,
        inputStream: java.io.InputStream,
        contentLength: Long
    ): String {
        val storageDir = FileManager.getStorageDir(context)
        val responsesDir = java.io.File(storageDir, "background_http_responses")
        if (!responsesDir.exists()) {
            responsesDir.mkdirs()
        }

        val responseFile = java.io.File(responsesDir, "${requestId}_response.txt")
        
        // Потоковое копирование данных (байты записываются напрямую, без форматирования)
        val bufferSize = 8192 // 8KB буфер
        val buffer = ByteArray(bufferSize)
        
        responseFile.outputStream().use { output ->
            var bytesRead: Int
            var totalBytesRead = 0L
            
            while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                output.write(buffer, 0, bytesRead)
                totalBytesRead += bytesRead
                
                // Логируем прогресс для больших файлов
                if (contentLength > 0 && totalBytesRead % (1024 * 1024) == 0L) {
                    val progress = (totalBytesRead * 100 / contentLength).toInt()
                    Log.d(TAG, "Downloading: $progress% ($totalBytesRead / $contentLength bytes)")
                }
            }
            output.flush()
        }

        Log.d(TAG, "Response saved to file: ${responseFile.absolutePath} (${responseFile.length()} bytes)")

        return responseFile.absolutePath
    }

}


