package com.tsitser.background_http_plugin

import android.content.Context
import android.util.Log
import androidx.work.Constraints
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.serialization.json.Json

/** BackgroundHttpClientPlugin */
class BackgroundHttpClientPlugin :
    FlutterPlugin,
    MethodCallHandler {
    
    private lateinit var channel: MethodChannel
    private var context: Context? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "background_http_client")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        val appContext = context ?: run {
            result.error("NO_CONTEXT", "Plugin context not available", null)
            return
        }

        when (call.method) {
            "executeRequest" -> {
                handleExecuteRequest(appContext, call, result)
            }
            "getRequestStatus" -> {
                handleGetRequestStatus(appContext, call, result)
            }
            "getResponse" -> {
                handleGetResponse(appContext, call, result)
            }
            "cancelRequest" -> {
                handleCancelRequest(appContext, call, result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    /**
     * Обрабатывает выполнение запроса
     */
    private fun handleExecuteRequest(
        context: Context,
        call: MethodCall,
        result: Result
    ) {
        try {
            @Suppress("UNCHECKED_CAST")
            val requestMap = call.arguments as? Map<*, *>
                ?: run {
                    result.error("INVALID_ARGUMENT", "Request data is required", null)
                    return
                }

            // Парсим запрос
            val request = parseRequest(requestMap)
            
            // Сохраняем запрос в файл
            val requestInfo = FileManager.saveRequest(context, request)

            // Если задача с таким ID уже существует, отменяем старые задачи
            // Это позволяет переиспользовать один и тот же requestId
            val workManager = WorkManager.getInstance(context)
            workManager.cancelAllWorkByTag("request_${requestInfo.requestId}")
            workManager.cancelAllWorkByTag("request_${requestInfo.requestId}_retry")
            workManager.cancelAllWorkByTag("request_${requestInfo.requestId}_network_wait")

            // Запускаем фоновую задачу через WorkManager
            // WorkManager автоматически выполняет задачи в фоне, даже после закрытия приложения
            val workRequest = OneTimeWorkRequestBuilder<HttpRequestWorker>()
                .setConstraints(
                    Constraints.Builder()
                        .setRequiredNetworkType(NetworkType.CONNECTED)
                        .build()
                )
                .setInputData(
                    androidx.work.Data.Builder()
                        .putString(HttpRequestWorker.KEY_REQUEST_ID, requestInfo.requestId)
                        .build()
                )
                // Добавляем тег для возможности отмены по ID
                .addTag("request_${requestInfo.requestId}")
                .build()

            workManager.enqueue(workRequest)

            // Возвращаем информацию о запросе
            result.success(
                mapOf(
                    "requestId" to requestInfo.requestId,
                    "requestFilePath" to requestInfo.requestFilePath
                )
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error executing request", e)
            result.error("EXECUTION_ERROR", e.message, null)
        }
    }

    /**
     * Обрабатывает получение статуса запроса
     */
    private fun handleGetRequestStatus(
        context: Context,
        call: MethodCall,
        result: Result
    ) {
        try {
            @Suppress("UNCHECKED_CAST")
            val args = call.arguments as? Map<*, *>
                ?: run {
                    result.error("INVALID_ARGUMENT", "Request ID is required", null)
                    return
                }

            val requestId = args["requestId"] as? String
                ?: run {
                    result.error("INVALID_ARGUMENT", "Request ID is required", null)
                    return
                }

            val statusInfo = FileManager.loadStatus(context, requestId)
                ?: run {
                    result.error("NOT_FOUND", "Request not found", null)
                    return
                }

            result.success(statusInfo.status.ordinal)
        } catch (e: Exception) {
            Log.e(TAG, "Error getting request status", e)
            result.error("STATUS_ERROR", e.message, null)
        }
    }

    /**
     * Обрабатывает получение ответа
     */
    private fun handleGetResponse(
        context: Context,
        call: MethodCall,
        result: Result
    ) {
        try {
            @Suppress("UNCHECKED_CAST")
            val args = call.arguments as? Map<*, *>
                ?: run {
                    result.error("INVALID_ARGUMENT", "Request ID is required", null)
                    return
                }

            val requestId = args["requestId"] as? String
                ?: run {
                    result.error("INVALID_ARGUMENT", "Request ID is required", null)
                    return
                }

            val response = FileManager.loadResponse(context, requestId)
                ?: run {
                    result.success(null)
                    return
                }

            result.success(
                mapOf(
                    "requestId" to response.requestId,
                    "statusCode" to response.statusCode,
                    "headers" to response.headers,
                    "body" to response.body,
                    "responseFilePath" to response.responseFilePath,
                    "status" to response.status.ordinal,
                    "error" to response.error
                )
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error getting response", e)
            result.error("RESPONSE_ERROR", e.message, null)
        }
    }

    /**
     * Обрабатывает отмену запроса
     */
    private fun handleCancelRequest(
        context: Context,
        call: MethodCall,
        result: Result
    ) {
        try {
            @Suppress("UNCHECKED_CAST")
            val args = call.arguments as? Map<*, *>
                ?: run {
                    result.error("INVALID_ARGUMENT", "Request ID is required", null)
                    return
                }

            val requestId = args["requestId"] as? String
                ?: run {
                    result.error("INVALID_ARGUMENT", "Request ID is required", null)
                    return
                }

            val workManager = WorkManager.getInstance(context)
            
            // Отменяем все WorkManager задачи для данного запроса:
            // 1. Основную задачу
            // 2. Задачи повторов
            // 3. Задачи ожидания сети
            workManager.cancelAllWorkByTag("request_$requestId")
            workManager.cancelAllWorkByTag("request_${requestId}_retry")
            workManager.cancelAllWorkByTag("request_${requestId}_network_wait")

            // Обновляем статус на FAILED
            FileManager.saveStatus(
                context,
                RequestStatusInfo(
                    requestId,
                    RequestStatus.FAILED,
                    "Request cancelled"
                )
            )

            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Error cancelling request", e)
            result.error("CANCEL_ERROR", e.message, null)
        }
    }

    /**
     * Парсит запрос из Map
     */
    @Suppress("UNCHECKED_CAST")
    private fun parseRequest(requestMap: Map<*, *>): HttpRequest {
        val headersMap: Map<String, String>? = (requestMap["headers"] as? Map<*, *>)?.let { map ->
            val result = mutableMapOf<String, String>()
            map.forEach { (key, value) ->
                if (key is String && value is String) {
                    result[key] = value
                }
            }
            result.ifEmpty { null }
        }
        
        val queryParamsMap: Map<String, String>? = (requestMap["queryParameters"] as? Map<*, *>)?.let { map ->
            val result = mutableMapOf<String, String>()
            map.forEach { (key, value) ->
                if (key is String) {
                    result[key] = value.toString()
                }
            }
            result.ifEmpty { null }
        }

        val multipartFieldsMap: Map<String, String>? = (requestMap["multipartFields"] as? Map<*, *>)?.let { map ->
            val result = mutableMapOf<String, String>()
            map.forEach { (key, value) ->
                if (key is String && value is String) {
                    result[key] = value
                }
            }
            result.ifEmpty { null }
        }

        val multipartFilesMap: Map<String, MultipartFile>? = (requestMap["multipartFiles"] as? Map<*, *>)?.let { map ->
            val result = mutableMapOf<String, MultipartFile>()
            map.forEach { (key, value) ->
                if (key is String && value is Map<*, *>) {
                    @Suppress("UNCHECKED_CAST")
                    val fileMap = value as Map<String, Any>
                    result[key] = MultipartFile(
                        filePath = fileMap["filePath"] as String,
                        filename = fileMap["filename"] as? String,
                        contentType = fileMap["contentType"] as? String
                    )
                }
            }
            result.ifEmpty { null }
        }
        
        return HttpRequest(
            url = requestMap["url"] as String,
            method = requestMap["method"] as String,
            headers = headersMap,
            body = requestMap["body"] as? String,
            queryParameters = queryParamsMap,
            timeout = (requestMap["timeout"] as? Number)?.toInt(),
            multipartFields = multipartFieldsMap,
            multipartFiles = multipartFilesMap,
            requestId = requestMap["requestId"] as? String,
            retries = (requestMap["retries"] as? Number)?.toInt()
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        context = null
    }

    companion object {
        private const val TAG = "BackgroundHttpClientPlugin"
    }
}
