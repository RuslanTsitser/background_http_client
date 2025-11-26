package com.tsitser.background_http_plugin.presentation.handler

import android.content.Context
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Обработчик EventChannel для отправки событий о завершенных задачах
 */
class TaskCompletedEventStreamHandler(private val context: Context) : EventChannel.StreamHandler {
    
    private var eventSink: EventChannel.EventSink? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    
    companion object {
        @Volatile
        private var instance: TaskCompletedEventStreamHandler? = null
        
        /**
         * Получает singleton экземпляр
         * Используется для отправки событий из HttpRequestWorker
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
     * Отправляет событие о завершенной задаче
     * Вызывается из HttpRequestWorker или других мест
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

