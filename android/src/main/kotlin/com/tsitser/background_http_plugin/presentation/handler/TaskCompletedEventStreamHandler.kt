package com.tsitser.background_http_plugin.presentation.handler

import android.content.Context
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * EventChannel handler for sending events about completed tasks.
 */
class TaskCompletedEventStreamHandler(private val context: Context) : EventChannel.StreamHandler {
    
    private var eventSink: EventChannel.EventSink? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    
    companion object {
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
    }
    
    init {
        instance = this
    }
    
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }
    
    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
    
    /**
     * Sends an event about a completed task.
     * Called from HttpRequestWorker or other places.
     */
    fun sendCompletedTask(requestId: String) {
        scope.launch(Dispatchers.Main) {
            eventSink?.success(requestId)
        }
    }
    
    fun cleanup() {
        scope.cancel()
        instance = null
    }
}

