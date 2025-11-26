import Flutter
import Foundation

/// Обработчик вызовов методов от Flutter
class MethodCallHandler {
    private let repository: TaskRepository
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
}

