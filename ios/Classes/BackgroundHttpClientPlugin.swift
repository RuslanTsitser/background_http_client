import Flutter
import Foundation
import UIKit

public class BackgroundHttpClientPlugin: NSObject, FlutterPlugin {

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "background_http_client", binaryMessenger: registrar.messenger())
    let instance = BackgroundHttpClientPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  override init() {
    super.init()
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "createRequest":
      // TODO: Реализовать создание HTTP запроса в нативном HTTP сервисе
      // Возвращает: Dictionary с полями id (String), status (Int), path (String), registrationDate (Int64 - timestamp в миллисекундах)
      result(FlutterMethodNotImplemented)
    case "getRequestStatus":
      // TODO: Реализовать получение статуса задачи по ID
      // Возвращает: Dictionary с полями id, status, path, registrationDate или nil если задача не найдена
      result(FlutterMethodNotImplemented)
    case "getResponse":
      // TODO: Реализовать получение ответа от сервера по ID задачи
      // Возвращает: Dictionary с полями id, status, path, registrationDate, responseJson или nil если задача не найдена
      result(FlutterMethodNotImplemented)
    case "cancelRequest":
      // TODO: Реализовать отмену задачи по ID
      // Возвращает: Bool? (true - отменена, false - не получилось, nil - не существует)
      result(FlutterMethodNotImplemented)
    case "deleteRequest":
      // TODO: Реализовать удаление задачи и всех связанных файлов по ID
      // Возвращает: Bool? (true - удалена, false - не получилось, nil - не существует)
      result(FlutterMethodNotImplemented)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
