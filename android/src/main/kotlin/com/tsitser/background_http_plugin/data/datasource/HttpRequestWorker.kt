package com.tsitser.background_http_plugin.data.datasource

import android.app.ActivityManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import com.tsitser.background_http_plugin.domain.entity.RequestStatus
import com.tsitser.background_http_plugin.presentation.handler.TaskCompletedEventStreamHandler
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
 * Worker for executing HTTP requests in the background.
 */
class HttpRequestWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    private val fileStorage = FileStorageDataSource(context)

    companion object {
        const val KEY_REQUEST_ID = "request_id"
        private const val TAG = "HttpRequestWorker"
        private const val CHANNEL_ID = "background_http_client_channel"
        private const val NOTIFICATION_ID = 1
    }

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val requestId = inputData.getString(KEY_REQUEST_ID)
            ?: return@withContext Result.failure()

        Log.d(TAG, "Starting HTTP request worker for requestId: $requestId")

        // Run as foreground worker when app is in foreground (Android 12+ restriction)
        // If app is in background for too long, starting foreground service is not allowed.
        try {
            if (isAppInForeground()) {
                setForeground(createForegroundInfo(requestId))
            } else {
                Log.w(TAG, "App in background; skipping ForegroundInfo for requestId: $requestId")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to set ForegroundInfo for requestId: $requestId", e)
        }

        try {
            val taskInfo = fileStorage.loadTaskInfo(requestId)
                ?: return@withContext Result.failure()
            
            // Load request from file
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
            
            // Parse multipartFields
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
            
            // Parse multipartFiles
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

            // Build URL with query parameters
            var requestUrl = url
            if (!queryParameters.isNullOrEmpty()) {
                val urlBuilder = url.toHttpUrlOrNull()?.newBuilder()
                queryParameters.forEach { (key, value) ->
                    urlBuilder?.addQueryParameter(key, value)
                }
                requestUrl = urlBuilder?.build()?.toString() ?: url
            }

            // Create OkHttp client
            val client = OkHttpClient.Builder()
                .connectTimeout(timeout.toLong(), TimeUnit.SECONDS)
                .readTimeout(timeout.toLong(), TimeUnit.SECONDS)
                .writeTimeout(timeout.toLong(), TimeUnit.SECONDS)
                .build()

            // Create request body
            val requestBody = when {
                !multipartFields.isNullOrEmpty() || !multipartFiles.isNullOrEmpty() -> {
                    buildMultipartBody(multipartFields, multipartFiles)
                }
                body != null && method != "GET" && method != "HEAD" -> {
                    body.toRequestBody("application/json".toMediaType())
                }
                else -> null
            }

            // Create request
            val requestBuilder = okhttp3.Request.Builder()
                .url(requestUrl)
                .method(method, requestBody)

            // Add headers (but not Content-Type for multipart; OkHttp will set it automatically)
            headers?.forEach { (key, value) ->
                if (requestBody == null || key.lowercase() != "content-type") {
                    requestBuilder.addHeader(key, value)
                }
            }

            // Execute request
            Log.d(TAG, "Executing HTTP request for requestId: $requestId, url: $requestUrl")
            val response = client.newCall(requestBuilder.build()).execute()
            Log.d(TAG, "HTTP request completed for requestId: $requestId, status: ${response.code}")

            // Handle response
            val responseBody = response.body?.string()
            val responseHeaders = response.headers.toMultimap().mapValues { it.value.firstOrNull() ?: "" }
            val statusCode = response.code

            val status = if (statusCode in 200..299) {
                RequestStatus.COMPLETED
            } else {
                RequestStatus.FAILED
            }

            // Save response
            val responseFilePath = responseBody?.let { saveResponseBody(requestId, it) }
            fileStorage.saveResponse(
                requestId = requestId,
                statusCode = statusCode,
                headers = responseHeaders,
                // Store only small responses in body
                body = responseBody?.takeIf { it.length <= 10000 },
                responseFilePath = responseFilePath,
                status = status,
                error = if (status == RequestStatus.FAILED) responseBody ?: "Request failed" else null
            )

            // Notify queue that the task is completed
            notifyTaskCompleted(requestId)
            
            // Send event only on successful completion
            if (status == RequestStatus.COMPLETED) {
                Log.d(TAG, "Request completed successfully for requestId: $requestId")
                sendTaskCompletedEvent(requestId)
            } else {
                Log.w(TAG, "Request failed for requestId: $requestId, status: $status")
            }

            Log.d(TAG, "HTTP request worker finished for requestId: $requestId")

            Result.success()
        } catch (e: CancellationException) {
            // Task cancellation is normal behavior, not an error
            // But we must notify the queue manager to free the slot!
            Log.d(TAG, "Request $requestId was cancelled")
            notifyTaskCompleted(requestId)
            
            // Rethrow to let WorkManager handle the cancellation correctly
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "Error executing request $requestId", e)
            
            // Check whether this is a network error that can be retried
            // Include SocketException and connection abort errors (common in Android 15+ background)
            val isNetworkError = e is java.net.UnknownHostException ||
                    e is java.net.ConnectException ||
                    e is java.net.SocketTimeoutException ||
                    e is java.net.SocketException ||
                    e is javax.net.ssl.SSLException ||
                    e is javax.net.ssl.SSLHandshakeException ||
                    (e is java.io.IOException && (
                        e.message?.contains("network", ignoreCase = true) == true ||
                        e.message?.contains("connection abort", ignoreCase = true) == true ||
                        e.message?.contains("connection closed", ignoreCase = true) == true ||
                        e.message?.contains("connection reset", ignoreCase = true) == true
                    )) ||
                    (e.cause is java.net.SocketException) ||
                    (e.cause is java.io.EOFException)
            
            // Check whether this is specifically a "no internet" error.
            // When there is no internet, WorkManager itself will wait for connectivity
            // thanks to NetworkType.CONNECTED, so we don't need to consume retries.
            val isNoInternetError = e is java.net.UnknownHostException ||
                    (e is java.net.ConnectException && e.message?.contains("Network is unreachable", ignoreCase = true) == true)
            
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
            
            // Do not send event on errors – only on successful completion
            // But notify the queue about completion (to start the next task)
            notifyTaskCompleted(requestId)
            
            // For network errors WorkManager will retry the task.
            // WorkManager has a NetworkType.CONNECTED constraint, so when there is no internet
            // the task will wait for connectivity without consuming WorkManager retry attempts.
            // The `retries` parameter from the request is not used to limit WorkManager attempts.
            if (isNetworkError) {
                Result.retry() // WorkManager will automatically retry on network errors
            } else {
                Result.failure() // Task finished with error, no retry needed
            }
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
    
    /**
     * Sends an event about a completed task through EventChannel.
     * Uses SharedPreferences queue since WorkManager may run in a different process.
     */
    private fun sendTaskCompletedEvent(requestId: String) {
        try {
            Log.d(TAG, "Queueing completed task event: $requestId")
            TaskCompletedEventStreamHandler.queueCompletedTask(applicationContext, requestId)
        } catch (e: Exception) {
            Log.e(TAG, "Error sending task completed event for $requestId", e)
        }
    }
    
    /**
     * Notifies TaskQueueManager that a task has been completed.
     * This allows the next task in the queue to be started.
     */
    private fun notifyTaskCompleted(requestId: String) {
        try {
            val queueManager = TaskQueueManager.getInstance(applicationContext)
            kotlinx.coroutines.runBlocking {
                queueManager.onTaskCompleted(requestId)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error notifying queue manager about task completion for $requestId", e)
        }
    }

    private fun createForegroundInfo(requestId: String): ForegroundInfo {
        createNotificationChannel()

        val pendingIntent = PendingIntent.getActivity(
            applicationContext,
            0,
            applicationContext.packageManager.getLaunchIntentForPackage(applicationContext.packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setContentTitle("Background HTTP Client")
            .setContentText("Processing request: ${requestId.take(20)}...")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setSilent(true)
            .build()

        val foregroundType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        } else {
            0
        }

        return ForegroundInfo(NOTIFICATION_ID, notification, foregroundType)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Background HTTP Requests",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows notification when HTTP requests are being processed in background"
                setShowBadge(false)
            }

            val notificationManager = applicationContext.getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun isAppInForeground(): Boolean {
        return try {
            val activityManager = applicationContext.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val runningProcesses = activityManager.runningAppProcesses ?: return false
            val packageName = applicationContext.packageName
            runningProcesses.any { process ->
                process.processName == packageName &&
                    (process.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND ||
                     process.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_VISIBLE)
            }
        } catch (e: Exception) {
            false
        }
    }
}

