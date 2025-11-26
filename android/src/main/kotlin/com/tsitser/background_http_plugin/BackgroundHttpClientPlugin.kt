package com.tsitser.background_http_plugin

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** BackgroundHttpClientPlugin */
class BackgroundHttpClientPlugin :
    FlutterPlugin,
    MethodCallHandler {
    
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "background_http_client")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "executeRequest" -> {
                // TODO: Реализовать выполнение HTTP запроса в фоновом режиме
                result.notImplemented()
            }
            "getRequestStatus" -> {
                // TODO: Реализовать получение статуса запроса по ID
                result.notImplemented()
            }
            "getResponse" -> {
                // TODO: Реализовать получение ответа от сервера по ID запроса
                result.notImplemented()
            }
            "cancelRequest" -> {
                // TODO: Реализовать отмену запроса по ID
                result.notImplemented()
            }
            "deleteRequest" -> {
                // TODO: Реализовать удаление запроса и всех связанных файлов по ID
                result.notImplemented()
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
