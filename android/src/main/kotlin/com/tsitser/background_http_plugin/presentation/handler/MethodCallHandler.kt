package com.tsitser.background_http_plugin.presentation.handler

import android.content.Context
import com.tsitser.background_http_plugin.data.mapper.RequestMapper
import com.tsitser.background_http_plugin.data.mapper.TaskInfoMapper
import com.tsitser.background_http_plugin.data.repository.TaskRepositoryImpl
import com.tsitser.background_http_plugin.domain.usecase.*
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Handler for method calls from Flutter.
 */
class MethodCallHandler(private val context: Context) : MethodChannel.MethodCallHandler {

    private val repository = TaskRepositoryImpl(context)
    private val createRequestUseCase = CreateRequestUseCase(repository)
    private val getRequestStatusUseCase = GetRequestStatusUseCase(repository)
    private val getResponseUseCase = GetResponseUseCase(repository)
    private val cancelRequestUseCase = CancelRequestUseCase(repository)
    private val deleteRequestUseCase = DeleteRequestUseCase(repository)

    private val scope = CoroutineScope(Dispatchers.Main)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "createRequest" -> handleCreateRequest(call, result)
            "getRequestStatus" -> handleGetRequestStatus(call, result)
            "getBatchRequestStatus" -> handleGetBatchRequestStatus(call, result)
            "getResponse" -> handleGetResponse(call, result)
            "cancelRequest" -> handleCancelRequest(call, result)
            "deleteRequest" -> handleDeleteRequest(call, result)
            "getPendingTasks" -> handleGetPendingTasks(call, result)
            "cancelAllTasks" -> handleCancelAllTasks(call, result)
            // New methods for queue management
            "getQueueStats" -> handleGetQueueStats(call, result)
            "setMaxConcurrentTasks" -> handleSetMaxConcurrentTasks(call, result)
            "setMaxQueueSize" -> handleSetMaxQueueSize(call, result)
            "syncQueueState" -> handleSyncQueueState(call, result)
            "processQueue" -> handleProcessQueue(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleCreateRequest(call: MethodCall, result: MethodChannel.Result) {
        try {
            @Suppress("UNCHECKED_CAST")
            val requestMap = call.arguments as? Map<*, *>
                ?: run {
                    result.error("INVALID_ARGUMENT", "Request data is required", null)
                    return
                }

            scope.launch {
                try {
                    val request = RequestMapper.fromFlutterMap(requestMap)
                    val taskInfo = withContext(Dispatchers.IO) {
                        createRequestUseCase(request)
                    }
                    val response = TaskInfoMapper.toFlutterMap(taskInfo)
                    result.success(response)
                } catch (e: Exception) {
                    android.util.Log.e("MethodCallHandler", "Error creating request", e)
                    result.error("CREATE_REQUEST_FAILED", "${e.message}\n${e.stackTraceToString()}", null)
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("MethodCallHandler", "Error parsing request", e)
            result.error("INVALID_ARGUMENT", "${e.message}\n${e.stackTraceToString()}", null)
        }
    }

    private fun handleGetRequestStatus(call: MethodCall, result: MethodChannel.Result) {
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

            scope.launch {
                try {
                    val taskInfo = withContext(Dispatchers.IO) {
                        getRequestStatusUseCase(requestId)
                    }
                    if (taskInfo != null) {
                        val response = TaskInfoMapper.toFlutterMap(taskInfo)
                        result.success(response)
                    } else {
                        result.success(null)
                    }
                } catch (e: Exception) {
                    result.error("GET_STATUS_FAILED", e.message, null)
                }
            }
        } catch (e: Exception) {
            result.error("INVALID_ARGUMENT", e.message, null)
        }
    }

    private fun handleGetBatchRequestStatus(call: MethodCall, result: MethodChannel.Result) {
        try {
            @Suppress("UNCHECKED_CAST")
            val args = call.arguments as? Map<*, *>
                ?: run {
                    result.error("INVALID_ARGUMENT", "Request IDs are required", null)
                    return
                }

            @Suppress("UNCHECKED_CAST")
            val requestIds = args["requestIds"] as? List<*>
                ?: run {
                    result.error("INVALID_ARGUMENT", "Request IDs list is required", null)
                    return
                }

            scope.launch {
                try {
                    val batchResult = withContext(Dispatchers.IO) {
                        val resultMap = mutableMapOf<String, Map<String, Any>?>()
                        for (requestIdObj in requestIds) {
                            val requestId = requestIdObj as? String ?: continue
                            val taskInfo = getRequestStatusUseCase(requestId)
                            if (taskInfo != null) {
                                resultMap[requestId] = TaskInfoMapper.toFlutterMap(taskInfo)
                            } else {
                                resultMap[requestId] = null
                            }
                        }
                        resultMap
                    }
                    result.success(batchResult)
                } catch (e: Exception) {
                    result.error("GET_BATCH_STATUS_FAILED", e.message, null)
                }
            }
        } catch (e: Exception) {
            result.error("INVALID_ARGUMENT", e.message, null)
        }
    }

    private fun handleGetResponse(call: MethodCall, result: MethodChannel.Result) {
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

            scope.launch {
                try {
                    val taskInfo = withContext(Dispatchers.IO) {
                        getResponseUseCase(requestId)
                    }
                    if (taskInfo != null) {
                        val response = TaskInfoMapper.toFlutterMap(taskInfo)
                        result.success(response)
                    } else {
                        result.success(null)
                    }
                } catch (e: Exception) {
                    result.error("GET_RESPONSE_FAILED", e.message, null)
                }
            }
        } catch (e: Exception) {
            result.error("INVALID_ARGUMENT", e.message, null)
        }
    }

    private fun handleCancelRequest(call: MethodCall, result: MethodChannel.Result) {
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

            scope.launch {
                try {
                    val cancelled = withContext(Dispatchers.IO) {
                        cancelRequestUseCase(requestId)
                    }
                    result.success(cancelled)
                } catch (e: Exception) {
                    result.error("CANCEL_REQUEST_FAILED", e.message, null)
                }
            }
        } catch (e: Exception) {
            result.error("INVALID_ARGUMENT", e.message, null)
        }
    }

    private fun handleDeleteRequest(call: MethodCall, result: MethodChannel.Result) {
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

            scope.launch {
                try {
                    val deleted = withContext(Dispatchers.IO) {
                        deleteRequestUseCase(requestId)
                    }
                    result.success(deleted)
                } catch (e: Exception) {
                    result.error("DELETE_REQUEST_FAILED", e.message, null)
                }
            }
        } catch (e: Exception) {
            result.error("INVALID_ARGUMENT", e.message, null)
        }
    }

    private fun handleGetPendingTasks(call: MethodCall, result: MethodChannel.Result) {
        scope.launch {
            try {
                val pendingTasks = withContext(Dispatchers.IO) {
                    repository.getPendingTasks()
                }
                val response = pendingTasks.map { task ->
                    mapOf(
                        "requestId" to task.requestId,
                        "registrationDate" to task.registrationDate
                    )
                }
                result.success(response)
            } catch (e: Exception) {
                android.util.Log.e("MethodCallHandler", "Error getting pending tasks", e)
                result.error("GET_PENDING_TASKS_FAILED", e.message, null)
            }
        }
    }

    private fun handleCancelAllTasks(call: MethodCall, result: MethodChannel.Result) {
        scope.launch {
            try {
                val count = withContext(Dispatchers.IO) {
                    repository.cancelAllTasks()
                }
                result.success(count)
            } catch (e: Exception) {
                android.util.Log.e("MethodCallHandler", "Error cancelling all tasks", e)
                result.error("CANCEL_ALL_TASKS_FAILED", e.message, null)
            }
        }
    }
    
    private fun handleGetQueueStats(call: MethodCall, result: MethodChannel.Result) {
        try {
            val stats = repository.getQueueStats()
            result.success(stats.toMap())
        } catch (e: Exception) {
            android.util.Log.e("MethodCallHandler", "Error getting queue stats", e)
            result.error("GET_QUEUE_STATS_FAILED", e.message, null)
        }
    }
    
    private fun handleSetMaxConcurrentTasks(call: MethodCall, result: MethodChannel.Result) {
        try {
            @Suppress("UNCHECKED_CAST")
            val args = call.arguments as? Map<*, *>
                ?: run {
                    result.error("INVALID_ARGUMENT", "Arguments are required", null)
                    return
                }
            
            val count = (args["count"] as? Number)?.toInt()
                ?: run {
                    result.error("INVALID_ARGUMENT", "count is required", null)
                    return
                }
            
            scope.launch {
                try {
                    withContext(Dispatchers.IO) {
                        repository.setMaxConcurrentTasks(count)
                    }
                    result.success(true)
                } catch (e: Exception) {
                    result.error("SET_MAX_CONCURRENT_FAILED", e.message, null)
                }
            }
        } catch (e: Exception) {
            result.error("INVALID_ARGUMENT", e.message, null)
        }
    }
    
    private fun handleSetMaxQueueSize(call: MethodCall, result: MethodChannel.Result) {
        try {
            @Suppress("UNCHECKED_CAST")
            val args = call.arguments as? Map<*, *>
                ?: run {
                    result.error("INVALID_ARGUMENT", "Arguments are required", null)
                    return
                }
            
            val size = (args["size"] as? Number)?.toInt()
                ?: run {
                    result.error("INVALID_ARGUMENT", "size is required", null)
                    return
                }
            
            repository.setMaxQueueSize(size)
            result.success(true)
        } catch (e: Exception) {
            result.error("SET_MAX_QUEUE_SIZE_FAILED", e.message, null)
        }
    }
    
    private fun handleSyncQueueState(call: MethodCall, result: MethodChannel.Result) {
        scope.launch {
            try {
                withContext(Dispatchers.IO) {
                    repository.syncQueueState()
                }
                result.success(true)
            } catch (e: Exception) {
                android.util.Log.e("MethodCallHandler", "Error syncing queue state", e)
                result.error("SYNC_QUEUE_STATE_FAILED", e.message, null)
            }
        }
    }
    
    private fun handleProcessQueue(call: MethodCall, result: MethodChannel.Result) {
        scope.launch {
            try {
                withContext(Dispatchers.IO) {
                    repository.processQueue()
                }
                result.success(true)
            } catch (e: Exception) {
                android.util.Log.e("MethodCallHandler", "Error processing queue", e)
                result.error("PROCESS_QUEUE_FAILED", e.message, null)
            }
        }
    }
}

