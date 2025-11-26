import Flutter
import Foundation

public class BackgroundHttpClientPlugin: NSObject, FlutterPlugin {
  private let methodCallHandler = MethodCallHandler()
  private var eventChannel: FlutterEventChannel?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "background_http_client", binaryMessenger: registrar.messenger())
    let instance = BackgroundHttpClientPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    
    // Регистрируем EventChannel для событий о завершенных задачах
    let eventChannel = FlutterEventChannel(
      name: "background_http_client/task_completed",
      binaryMessenger: registrar.messenger()
    )
    eventChannel.setStreamHandler(TaskCompletedEventStreamHandler.shared)
    instance.eventChannel = eventChannel
  }

  override init() {
    super.init()
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    methodCallHandler.handle(call, result: result)
  }
}
