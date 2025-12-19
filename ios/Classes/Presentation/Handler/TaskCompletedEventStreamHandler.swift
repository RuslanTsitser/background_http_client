import Flutter
import Foundation

/// EventChannel handler for sending events about completed tasks
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
    
    /// Sends an event about a completed task.
    /// Called from URLSessionDataSource or other places.
    func sendCompletedTask(requestId: String) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(requestId)
        }
    }
}

