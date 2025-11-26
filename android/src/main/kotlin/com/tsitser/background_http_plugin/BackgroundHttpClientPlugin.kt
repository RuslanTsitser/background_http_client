package com.tsitser.background_http_plugin

import com.tsitser.background_http_plugin.presentation.handler.MethodCallHandler
import com.tsitser.background_http_plugin.presentation.handler.TaskCompletedEventStreamHandler
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/** BackgroundHttpClientPlugin */
class BackgroundHttpClientPlugin : FlutterPlugin {
    
    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var methodCallHandler: MethodCallHandler
    private lateinit var eventStreamHandler: TaskCompletedEventStreamHandler

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "background_http_client")
        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "background_http_client/task_completed")
        methodCallHandler = MethodCallHandler(flutterPluginBinding.applicationContext)
        eventStreamHandler = TaskCompletedEventStreamHandler(flutterPluginBinding.applicationContext)
        channel.setMethodCallHandler(methodCallHandler)
        eventChannel.setStreamHandler(eventStreamHandler)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventStreamHandler.cleanup()
    }
}
