import Flutter
import Foundation

public class BackgroundHttpClientPlugin: NSObject, FlutterPlugin {
  private let methodCallHandler = MethodCallHandler()

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
    methodCallHandler.handle(call, result: result)
  }
}
