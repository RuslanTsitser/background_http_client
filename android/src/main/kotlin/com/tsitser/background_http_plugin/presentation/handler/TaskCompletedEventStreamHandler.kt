package com.tsitser.background_http_plugin.presentation.handler

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.json.JSONArray

/**
 * EventChannel handler for sending events about completed tasks.
 * 
 * NOTE: WorkManager runs in a separate process, so we use SharedPreferences
 * to queue completed tasks and deliver them when Flutter is listening.
 */
class TaskCompletedEventStreamHandler(private val context: Context) : EventChannel.StreamHandler {
    
    private var eventSink: EventChannel.EventSink? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val prefs: SharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    
    companion object {
        private const val TAG = "TaskCompletedHandler"
        private const val PREFS_NAME = "background_http_completed_tasks"
        private const val KEY_PENDING_TASKS = "pending_completed_tasks"
        
        @Volatile
        private var instance: TaskCompletedEventStreamHandler? = null
        
        /**
         * Returns the singleton instance.
         * Used for sending events from HttpRequestWorker.
         */
        fun getInstance(context: Context): TaskCompletedEventStreamHandler {
            return instance ?: synchronized(this) {
                instance ?: TaskCompletedEventStreamHandler(context).also { instance = it }
            }
        }
        
        /**
         * Queues a completed task ID to SharedPreferences.
         * Called from HttpRequestWorker which may run in a different process.
         */
        fun queueCompletedTask(context: Context, requestId: String) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            synchronized(this) {
                val pendingJson = prefs.getString(KEY_PENDING_TASKS, "[]") ?: "[]"
                val pending = try {
                    JSONArray(pendingJson)
                } catch (e: Exception) {
                    JSONArray()
                }
                pending.put(requestId)
                prefs.edit().putString(KEY_PENDING_TASKS, pending.toString()).apply()
                Log.d(TAG, "Queued completed task: $requestId (total pending: ${pending.length()})")
            }
            
            // Also try to send directly if instance exists
            instance?.let {
                it.scope.launch(Dispatchers.Main) {
                    it.deliverPendingTasks()
                }
            }
        }
    }
    
    init {
        instance = this
        Log.d(TAG, "TaskCompletedEventStreamHandler initialized")
    }
    
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        Log.d(TAG, "onListen called, eventSink set: ${events != null}")
        eventSink = events
        // Deliver any pending tasks that were queued while Flutter wasn't listening
        deliverPendingTasks()
    }
    
    override fun onCancel(arguments: Any?) {
        Log.d(TAG, "onCancel called")
        eventSink = null
    }
    
    /**
     * Sends an event about a completed task.
     * Called from HttpRequestWorker or other places.
     */
    fun sendCompletedTask(requestId: String) {
        Log.d(TAG, "sendCompletedTask called: $requestId, eventSink=${eventSink != null}")
        scope.launch(Dispatchers.Main) {
            if (eventSink != null) {
                eventSink?.success(requestId)
                Log.d(TAG, "Sent task completed event: $requestId")
            } else {
                // Queue for later delivery
                queueCompletedTaskLocally(requestId)
            }
        }
    }
    
    private fun queueCompletedTaskLocally(requestId: String) {
        synchronized(Companion) {
            val pendingJson = prefs.getString(KEY_PENDING_TASKS, "[]") ?: "[]"
            val pending = try {
                JSONArray(pendingJson)
            } catch (e: Exception) {
                JSONArray()
            }
            pending.put(requestId)
            prefs.edit().putString(KEY_PENDING_TASKS, pending.toString()).apply()
            Log.d(TAG, "Queued task locally: $requestId (total pending: ${pending.length()})")
        }
    }
    
    /**
     * Delivers all pending tasks that were queued while eventSink was null.
     */
    private fun deliverPendingTasks() {
        if (eventSink == null) {
            Log.d(TAG, "Cannot deliver pending tasks - eventSink is null")
            return
        }
        
        synchronized(Companion) {
            val pendingJson = prefs.getString(KEY_PENDING_TASKS, "[]") ?: "[]"
            val pending = try {
                JSONArray(pendingJson)
            } catch (e: Exception) {
                Log.e(TAG, "Error parsing pending tasks", e)
                JSONArray()
            }
            
            if (pending.length() == 0) {
                return
            }
            
            Log.d(TAG, "Delivering ${pending.length()} pending tasks")
            
            for (i in 0 until pending.length()) {
                val requestId = pending.optString(i)
                if (requestId.isNotEmpty()) {
                    eventSink?.success(requestId)
                    Log.d(TAG, "Delivered pending task: $requestId")
                }
            }
            
            // Clear pending tasks
            prefs.edit().putString(KEY_PENDING_TASKS, "[]").apply()
            Log.d(TAG, "Cleared pending tasks queue")
        }
    }
    
    fun cleanup() {
        Log.d(TAG, "cleanup called")
        scope.cancel()
        instance = null
    }
}

