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
            "createRequest" -> {
                // TODO: Реализовать создание HTTP запроса в нативном HTTP сервисе
                // Возвращает: Map с полями id (String), status (Int), path (String), registrationDate (Long - timestamp в миллисекундах)
                result.notImplemented()
            }
            "getRequestStatus" -> {
                // TODO: Реализовать получение статуса задачи по ID
                // Возвращает: Map с полями id, status, path, registrationDate или null если задача не найдена
                result.notImplemented()
            }
            "getResponse" -> {
                // TODO: Реализовать получение ответа от сервера по ID задачи
                // Возвращает: Map с полями id, status, path, registrationDate, responseJson или null если задача не найдена
                result.notImplemented()
            }
            "cancelRequest" -> {
                // TODO: Реализовать отмену задачи по ID
                // Возвращает: Boolean (true - отменена, false - не получилось, null - не существует)
                result.notImplemented()
            }
            "deleteRequest" -> {
                // TODO: Реализовать удаление задачи и всех связанных файлов по ID
                // Возвращает: Boolean (true - удалена, false - не получилось, null - не существует)
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
