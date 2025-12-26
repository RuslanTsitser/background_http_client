import Flutter
import Foundation

/// Handler for method calls from Flutter
class MethodCallHandler {
    private let repository: TaskRepositoryImpl
    private let createRequestUseCase: CreateRequestUseCase
    private let getRequestStatusUseCase: GetRequestStatusUseCase
    private let getResponseUseCase: GetResponseUseCase
    private let cancelRequestUseCase: CancelRequestUseCase
    private let deleteRequestUseCase: DeleteRequestUseCase
    
    init() {
        self.repository = TaskRepositoryImpl()
        self.createRequestUseCase = CreateRequestUseCase(repository: repository)
        self.getRequestStatusUseCase = GetRequestStatusUseCase(repository: repository)
        self.getResponseUseCase = GetResponseUseCase(repository: repository)
        self.cancelRequestUseCase = CancelRequestUseCase(repository: repository)
        self.deleteRequestUseCase = DeleteRequestUseCase(repository: repository)
    }
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "createRequest":
            handleCreateRequest(call: call, result: result)
        case "getRequestStatus":
            handleGetRequestStatus(call: call, result: result)
        case "getBatchRequestStatus":
            handleGetBatchRequestStatus(call: call, result: result)
        case "getResponse":
            handleGetResponse(call: call, result: result)
        case "cancelRequest":
            handleCancelRequest(call: call, result: result)
        case "deleteRequest":
            handleDeleteRequest(call: call, result: result)
        case "getPendingTasks":
            handleGetPendingTasks(call: call, result: result)
        case "cancelAllTasks":
            handleCancelAllTasks(call: call, result: result)
        // New methods for queue management
        case "getQueueStats":
            handleGetQueueStats(call: call, result: result)
        case "setMaxConcurrentTasks":
            handleSetMaxConcurrentTasks(call: call, result: result)
        case "setMaxQueueSize":
            handleSetMaxQueueSize(call: call, result: result)
        case "syncQueueState":
            handleSyncQueueState(call: call, result: result)
        case "processQueue":
            handleProcessQueue(call: call, result: result)
        case "getPendingCompletedTasks":
            handleGetPendingCompletedTasks(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func handleCreateRequest(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Request data is required", details: nil))
            return
        }
        
        Task {
            do {
                let request = RequestMapper.fromFlutterMap(args)
                let taskInfo = try await createRequestUseCase.execute(request: request)
                let response = TaskInfoMapper.toFlutterMap(taskInfo)
                result(response)
            } catch {
                result(FlutterError(code: "CREATE_REQUEST_FAILED", message: error.localizedDescription, details: nil))
            }
        }
    }
    
    private func handleGetRequestStatus(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let requestId = args["requestId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Request ID is required", details: nil))
            return
        }
        
        Task {
            do {
                let taskInfo = try await getRequestStatusUseCase.execute(requestId: requestId)
                if let taskInfo = taskInfo {
                    let response = TaskInfoMapper.toFlutterMap(taskInfo)
                    result(response)
                } else {
                    result(nil)
                }
            } catch {
                result(FlutterError(code: "GET_STATUS_FAILED", message: error.localizedDescription, details: nil))
            }
        }
    }
    
    private func handleGetBatchRequestStatus(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let requestIds = args["requestIds"] as? [String] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Request IDs list is required", details: nil))
            return
        }
        
        Task {
            do {
                var batchResult: [String: [String: Any]?] = [:]
                for requestId in requestIds {
                    let taskInfo = try await getRequestStatusUseCase.execute(requestId: requestId)
                    if let taskInfo = taskInfo {
                        batchResult[requestId] = TaskInfoMapper.toFlutterMap(taskInfo)
                    } else {
                        batchResult[requestId] = nil
                    }
                }
                result(batchResult)
            } catch {
                result(FlutterError(code: "GET_BATCH_STATUS_FAILED", message: error.localizedDescription, details: nil))
            }
        }
    }
    
    private func handleGetResponse(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let requestId = args["requestId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Request ID is required", details: nil))
            return
        }
        
        Task {
            do {
                let taskInfo = try await getResponseUseCase.execute(requestId: requestId)
                if let taskInfo = taskInfo {
                    let response = TaskInfoMapper.toFlutterMap(taskInfo)
                    result(response)
                } else {
                    result(nil)
                }
            } catch {
                result(FlutterError(code: "GET_RESPONSE_FAILED", message: error.localizedDescription, details: nil))
            }
        }
    }
    
    private func handleCancelRequest(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let requestId = args["requestId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Request ID is required", details: nil))
            return
        }
        
        Task {
            do {
                let cancelled = try await cancelRequestUseCase.execute(requestId: requestId)
                result(cancelled)
            } catch {
                result(FlutterError(code: "CANCEL_REQUEST_FAILED", message: error.localizedDescription, details: nil))
            }
        }
    }
    
    private func handleDeleteRequest(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let requestId = args["requestId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Request ID is required", details: nil))
            return
        }
        
        Task {
            do {
                let deleted = try await deleteRequestUseCase.execute(requestId: requestId)
                result(deleted)
            } catch {
                result(FlutterError(code: "DELETE_REQUEST_FAILED", message: error.localizedDescription, details: nil))
            }
        }
    }
    
    private func handleGetPendingTasks(call: FlutterMethodCall, result: @escaping FlutterResult) {
        Task {
            do {
                let pendingTasks = try await repository.getPendingTasks()
                let response = pendingTasks.map { task in
                    [
                        "requestId": task.requestId,
                        "registrationDate": task.registrationDate
                    ]
                }
                result(response)
            } catch {
                result(FlutterError(code: "GET_PENDING_TASKS_FAILED", message: error.localizedDescription, details: nil))
            }
        }
    }
    
    private func handleCancelAllTasks(call: FlutterMethodCall, result: @escaping FlutterResult) {
        Task {
            do {
                let count = try await repository.cancelAllTasks()
                result(count)
            } catch {
                result(FlutterError(code: "CANCEL_ALL_TASKS_FAILED", message: error.localizedDescription, details: nil))
            }
        }
    }
    
    // MARK: - Queue Management Methods
    
    private func handleGetQueueStats(call: FlutterMethodCall, result: @escaping FlutterResult) {
        Task {
            let stats = await repository.getQueueStats()
            result(stats.toDict())
        }
    }
    
    private func handleSetMaxConcurrentTasks(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let count = args["count"] as? Int else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "count is required", details: nil))
            return
        }
        
        Task {
            await repository.setMaxConcurrentTasks(count)
            result(true)
        }
    }
    
    private func handleSetMaxQueueSize(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let size = args["size"] as? Int else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "size is required", details: nil))
            return
        }
        
        Task {
            await repository.setMaxQueueSize(size)
            result(true)
        }
    }
    
    private func handleSyncQueueState(call: FlutterMethodCall, result: @escaping FlutterResult) {
        // On iOS, synchronization is not required because we use an actor
        result(true)
    }
    
    private func handleProcessQueue(call: FlutterMethodCall, result: @escaping FlutterResult) {
        Task {
            await repository.processQueue()
            result(true)
        }
    }
    
    /// Gets pending completed tasks from UserDefaults queue and delivers them.
    /// This is a fallback for when the EventChannel couldn't deliver events directly.
    private func handleGetPendingCompletedTasks(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let pendingTasks = TaskCompletedEventStreamHandler.getPendingCompletedTasks()
        result(pendingTasks)
    }
}

