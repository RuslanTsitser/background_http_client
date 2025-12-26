import Flutter
import Foundation

/// EventChannel handler for sending events about completed tasks.
///
/// NOTE: On iOS, background tasks might run while Flutter engine is not active,
/// so we use UserDefaults to queue completed tasks and deliver them when Flutter is listening.
class TaskCompletedEventStreamHandler: NSObject, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    
    private static let prefsKey = "background_http_pending_completed_tasks"
    
    static let shared = TaskCompletedEventStreamHandler()
    
    private override init() {
        super.init()
        print("[TaskCompletedHandler] initialized")
    }
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        print("[TaskCompletedHandler] onListen called")
        eventSink = events
        // Deliver any pending tasks that were queued while Flutter wasn't listening
        deliverPendingTasks()
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        print("[TaskCompletedHandler] onCancel called")
        eventSink = nil
        return nil
    }
    
    /// Sends an event about a completed task.
    /// Called from URLSessionDataSource or other places.
    func sendCompletedTask(requestId: String) {
        print("[TaskCompletedHandler] sendCompletedTask: \(requestId), eventSink=\(eventSink != nil)")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if let sink = self.eventSink {
                sink(requestId)
                print("[TaskCompletedHandler] Sent task completed event: \(requestId)")
            } else {
                // Queue for later delivery
                self.queueCompletedTask(requestId: requestId)
            }
        }
    }
    
    /// Queues a completed task ID to UserDefaults.
    private func queueCompletedTask(requestId: String) {
        let defaults = UserDefaults.standard
        var pending = defaults.stringArray(forKey: TaskCompletedEventStreamHandler.prefsKey) ?? []
        pending.append(requestId)
        defaults.set(pending, forKey: TaskCompletedEventStreamHandler.prefsKey)
        print("[TaskCompletedHandler] Queued task: \(requestId) (total pending: \(pending.count))")
    }
    
    /// Delivers all pending tasks that were queued while eventSink was nil.
    private func deliverPendingTasks() {
        guard let sink = eventSink else {
            print("[TaskCompletedHandler] Cannot deliver pending tasks - eventSink is nil")
            return
        }
        
        let defaults = UserDefaults.standard
        let pending = defaults.stringArray(forKey: TaskCompletedEventStreamHandler.prefsKey) ?? []
        
        if pending.isEmpty {
            return
        }
        
        print("[TaskCompletedHandler] Delivering \(pending.count) pending tasks")
        
        for requestId in pending {
            sink(requestId)
            print("[TaskCompletedHandler] Delivered pending task: \(requestId)")
        }
        
        // Clear pending tasks
        defaults.removeObject(forKey: TaskCompletedEventStreamHandler.prefsKey)
        print("[TaskCompletedHandler] Cleared pending tasks queue")
    }
    
    /// Gets pending completed tasks from UserDefaults and clears the queue.
    /// Called from MethodCallHandler for the Flutter polling fallback.
    static func getPendingCompletedTasks() -> [String] {
        let defaults = UserDefaults.standard
        let pending = defaults.stringArray(forKey: prefsKey) ?? []
        
        if !pending.isEmpty {
            defaults.removeObject(forKey: prefsKey)
            print("[TaskCompletedHandler] Returned \(pending.count) pending completed tasks")
        }
        
        return pending
    }
}

