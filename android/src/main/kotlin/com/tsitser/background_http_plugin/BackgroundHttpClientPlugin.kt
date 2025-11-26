package com.tsitser.background_http_plugin

import com.tsitser.background_http_plugin.presentation.handler.MethodCallHandler
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel

/** BackgroundHttpClientPlugin */
class BackgroundHttpClientPlugin : FlutterPlugin {
    
    private lateinit var channel: MethodChannel
    private lateinit var methodCallHandler: MethodCallHandler

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "background_http_client")
        methodCallHandler = MethodCallHandler(flutterPluginBinding.applicationContext)
        channel.setMethodCallHandler(methodCallHandler)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
