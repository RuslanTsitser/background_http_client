import Flutter
import Foundation

/// Обработчик EventChannel для отправки событий о завершенных задачах
class TaskCompletedEventStreamHandler: NSObject, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    
    static let shared = TaskCompletedEventStreamHandler()
    
    private override init() {
        super.init()
    }
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
    
    /// Отправляет событие о завершенной задаче
    /// Вызывается из URLSessionDataSource или других мест
    func sendCompletedTask(requestId: String) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(requestId)
        }
    }
}

