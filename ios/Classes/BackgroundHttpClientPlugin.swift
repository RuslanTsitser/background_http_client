import Flutter
import UIKit
import Foundation

public class BackgroundHttpClientPlugin: NSObject, FlutterPlugin, URLSessionDelegate {
    private var activeTasks: [String: URLSessionDataTask] = [:]
    // Множество отмененных запросов (для предотвращения выполнения запланированных повторных попыток)
    private var cancelledRequestIds = Set<String>()
    // Используем обычный URLSession для HTTP запросов
    // Background URLSession предназначен для downloadTask/uploadTask, а не для dataTask
    // Обычный URLSession работает в фоне, когда приложение свернуто
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 4 * 60 * 60 // 4 часа для больших файлов
        // Используем обычную конфигурацию без delegate для простоты
        return URLSession(configuration: config)
    }()
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "background_http_client", binaryMessenger: registrar.messenger())
        let instance = BackgroundHttpClientPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    override init() {
        super.init()
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "executeRequest":
            handleExecuteRequest(call: call, result: result)
        case "getRequestStatus":
            handleGetRequestStatus(call: call, result: result)
        case "getResponse":
            handleGetResponse(call: call, result: result)
        case "cancelRequest":
            handleCancelRequest(call: call, result: result)
        case "deleteRequest":
            handleDeleteRequest(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func handleExecuteRequest(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let urlString = args["url"] as? String,
              let method = args["method"] as? String,
              let url = URL(string: urlString) else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid request data", details: nil))
            return
        }
        
        // Используем кастомный ID, если указан, иначе генерируем автоматически
        let requestId = args["requestId"] as? String ?? UUID().uuidString
        let headers = args["headers"] as? [String: String]
        let body = args["body"] as? String
        let queryParameters = args["queryParameters"] as? [String: Any]
        let timeout = args["timeout"] as? Int ?? 30
        let multipartFields = args["multipartFields"] as? [String: String]
        let multipartFiles = args["multipartFiles"] as? [String: [String: Any]]
        let retries = (args["retries"] as? Int) ?? 0
        
        // Если задача с таким ID уже существует, отменяем старую задачу
        // и очищаем из множества отмененных (чтобы новая задача могла выполниться)
        if let existingTask = activeTasks[requestId] {
            existingTask.cancel()
            activeTasks.removeValue(forKey: requestId)
        }
        cancelledRequestIds.remove(requestId)
        
        // Сохраняем запрос в файл
        let requestInfo = saveRequest(
            requestId: requestId,
            url: urlString,
            method: method,
            headers: headers,
            body: body,
            queryParameters: queryParameters,
            timeout: timeout,
            multipartFields: multipartFields,
            multipartFiles: multipartFiles
        )
        
        // Обновляем статус на "в процессе"
        saveStatus(requestId: requestId, status: 0) // 0 = IN_PROGRESS
        
        // Выполняем запрос в фоне с поддержкой повторных попыток
        executeHttpRequestWithRetries(
            requestId: requestId,
            url: url,
            method: method,
            headers: headers,
            body: body,
            queryParameters: queryParameters,
            timeout: timeout,
            multipartFields: multipartFields,
            multipartFiles: multipartFiles,
            retries: retries,
            retriesRemaining: retries
        )
        
        result([
            "requestId": requestInfo.requestId,
            "requestFilePath": requestInfo.requestFilePath
        ])
    }
    
    private func handleGetRequestStatus(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let requestId = args["requestId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Request ID is required", details: nil))
            return
        }
        
        if let status = loadStatus(requestId: requestId) {
            result(status)
        } else {
            result(FlutterError(code: "NOT_FOUND", message: "Request not found", details: nil))
        }
    }
    
    private func handleGetResponse(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let requestId = args["requestId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Request ID is required", details: nil))
            return
        }
        
        if let response = loadResponse(requestId: requestId) {
            result(response)
        } else {
            result(nil)
        }
    }
    
    private func handleCancelRequest(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let requestId = args["requestId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Request ID is required", details: nil))
            return
        }
        
        // Помечаем запрос как отмененный (для предотвращения выполнения запланированных повторных попыток)
        cancelledRequestIds.insert(requestId)
        
        // Отменяем активную задачу
        if let task = activeTasks[requestId] {
            task.cancel()
            activeTasks.removeValue(forKey: requestId)
        }
        
        // Обновляем статус
        saveStatus(requestId: requestId, status: 2, error: "Request cancelled") // 2 = FAILED
        
        result(nil)
    }
    
    private func handleDeleteRequest(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let requestId = args["requestId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Request ID is required", details: nil))
            return
        }
        
        // Помечаем запрос как отмененный
        cancelledRequestIds.insert(requestId)
        
        // Отменяем активную задачу
        if let task = activeTasks[requestId] {
            task.cancel()
            activeTasks.removeValue(forKey: requestId)
        }
        
        // Удаляем все файлы, связанные с запросом
        deleteRequestFiles(requestId: requestId)
        
        result(nil)
    }
    
    // MARK: - HTTP Request Execution
    
    /// Выполняет HTTP запрос с поддержкой повторных попыток
    private func executeHttpRequestWithRetries(
        requestId: String,
        url: URL,
        method: String,
        headers: [String: String]?,
        body: String?,
        queryParameters: [String: Any]?,
        timeout: Int,
        multipartFields: [String: String]? = nil,
        multipartFiles: [String: [String: Any]]? = nil,
        retries: Int,
        retriesRemaining: Int
    ) {
        executeHttpRequest(
            requestId: requestId,
            url: url,
            method: method,
            headers: headers,
            body: body,
            queryParameters: queryParameters,
            timeout: timeout,
            multipartFields: multipartFields,
            multipartFiles: multipartFiles,
            retries: retries,
            retriesRemaining: retriesRemaining
        )
    }
    
    /// Выполняет HTTP запрос (одна попытка)
    private func executeHttpRequest(
        requestId: String,
        url: URL,
        method: String,
        headers: [String: String]?,
        body: String?,
        queryParameters: [String: Any]?,
        timeout: Int,
        multipartFields: [String: String]? = nil,
        multipartFiles: [String: [String: Any]]? = nil,
        retries: Int = 0,
        retriesRemaining: Int = 0
    ) {
        // Проверяем, не отменен ли запрос
        if cancelledRequestIds.contains(requestId) {
            print("BackgroundHttpClient: Request \(requestId) was cancelled, skipping execution")
            return
        }
        
        var requestURL = url
        
        // Добавляем query параметры
        if let queryParams = queryParameters, !queryParams.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            var queryItems: [URLQueryItem] = []
            for (key, value) in queryParams {
                queryItems.append(URLQueryItem(name: key, value: "\(value)"))
            }
            components?.queryItems = queryItems
            if let finalURL = components?.url {
                requestURL = finalURL
            }
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.timeoutInterval = TimeInterval(timeout)
        
        // Проверяем, является ли это multipart запросом
        let isMultipart = multipartFields != nil || multipartFiles != nil
        
        // Устанавливаем заголовки ПЕРЕД установкой тела запроса
        // Это важно, чтобы Content-Type и другие заголовки были установлены правильно
        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Устанавливаем User-Agent, если не указан явно
        // Это помогает избежать проблем с серверами, которые блокируют запросы без User-Agent
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue("BackgroundHttpClient/1.0", forHTTPHeaderField: "User-Agent")
        }
        
        // Устанавливаем тело запроса
        if isMultipart {
            // Multipart запрос
            let boundary = "----WebKitFormBoundary\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            
            var bodyData = Data()
            let lineFeed = "\r\n".data(using: .utf8)!
            let boundaryData = "--\(boundary)".data(using: .utf8)!
            
            // Добавляем поля
            multipartFields?.forEach { key, value in
                bodyData.append(boundaryData)
                bodyData.append(lineFeed)
                bodyData.append("Content-Disposition: form-data; name=\"\(key)\"".data(using: .utf8)!)
                bodyData.append(lineFeed)
                bodyData.append(lineFeed)
                bodyData.append(value.data(using: .utf8)!)
                bodyData.append(lineFeed)
            }
            
            // Добавляем файлы
            multipartFiles?.forEach { fieldName, fileInfo in
                guard let filePath = fileInfo["filePath"] as? String else { return }
                let fileURL = URL(fileURLWithPath: filePath)
                
                guard FileManager.default.fileExists(atPath: filePath),
                      let fileData = try? Data(contentsOf: fileURL) else {
                    return
                }
                
                let filename = fileInfo["filename"] as? String ?? fileURL.lastPathComponent
                let contentType = fileInfo["contentType"] as? String ?? "application/octet-stream"
                
                bodyData.append(boundaryData)
                bodyData.append(lineFeed)
                bodyData.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"".data(using: .utf8)!)
                bodyData.append(lineFeed)
                bodyData.append("Content-Type: \(contentType)".data(using: .utf8)!)
                bodyData.append(lineFeed)
                bodyData.append(lineFeed)
                bodyData.append(fileData)
                bodyData.append(lineFeed)
            }
            
            // Завершающий boundary
            bodyData.append("--\(boundary)--".data(using: .utf8)!)
            bodyData.append(lineFeed)
            
            request.httpBody = bodyData
            // Устанавливаем Content-Length для multipart запросов
            // Важно: устанавливаем ПОСЛЕ установки httpBody, чтобы размер был правильным
            request.setValue("\(bodyData.count)", forHTTPHeaderField: "Content-Length")
        } else if method != "GET" && method != "HEAD" {
            // Обычный запрос с телом (только для POST, PUT, PATCH)
            // Проверяем, сохранен ли body в файл
            let bodyFilePath = getBodyFilePath(requestId: requestId)
            var bodyData: Data? = nil
            
            if let bodyFilePath = bodyFilePath {
                // Читаем из файла
                let bodyFileURL = URL(fileURLWithPath: bodyFilePath)
                if FileManager.default.fileExists(atPath: bodyFilePath) {
                    bodyData = try? Data(contentsOf: bodyFileURL)
                    print("BackgroundHttpClient: Reading body from file: \(bodyFilePath), size: \(bodyData?.count ?? 0)")
                } else {
                    print("BackgroundHttpClient: Body file not found: \(bodyFilePath)")
                }
            } else if let bodyString = body {
                // Для обратной совместимости (если body не был сохранен в файл)
                bodyData = bodyString.data(using: .utf8)
            }
            
            if let bodyData = bodyData {
                request.httpBody = bodyData
                // Устанавливаем Content-Length
                request.setValue("\(bodyData.count)", forHTTPHeaderField: "Content-Length")
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
            }
        }
        
        // Выполняем запрос через URLSession
        // Обычный URLSession работает в фоне, когда приложение свернуто
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            self.activeTasks.removeValue(forKey: requestId)
            
            // Захватываем переменные для использования в замыкании
            let currentRetries = retries
            let currentRetriesRemaining = retriesRemaining
            
            if let error = error {
                let errorDescription = "Network error: \(error.localizedDescription)"
                let detailedError: String
                var isNetworkError = false
                
                if let urlError = error as? URLError {
                    detailedError = "URLError code: \(urlError.code.rawValue), description: \(urlError.localizedDescription)"
                    // Проверяем, является ли это сетевой ошибкой
                    isNetworkError = urlError.code == .notConnectedToInternet ||
                                    urlError.code == .networkConnectionLost ||
                                    urlError.code == .cannotFindHost ||
                                    urlError.code == .cannotConnectToHost ||
                                    urlError.code == .timedOut ||
                                    urlError.code == .dnsLookupFailed
                } else {
                    detailedError = errorDescription
                }
                
                // При сетевой ошибке всегда пытаемся повторить (если есть попытки)
                // или ждем появления сети
                if isNetworkError {
                    if currentRetriesRemaining > 0 {
                        // Есть попытки - повторяем
                    } else {
                        // Нет попыток, но это сетевая ошибка - обновляем статус на "ожидание сети"
                        print("BackgroundHttpClient: Network error for request \(requestId), waiting for network connection")
                        self.saveStatus(requestId: requestId, status: 0, error: "Waiting for network connection... (\(detailedError))")
                        
                        // Повторяем запрос через некоторое время (даже без retries)
                        // Это позволяет автоматически повторить при появлении сети
                        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(30)) { [weak self] in
                            guard let self = self else { return }
                            // Проверяем, не отменен ли запрос перед повторной попыткой
                            if self.cancelledRequestIds.contains(requestId) {
                                print("BackgroundHttpClient: Request \(requestId) was cancelled, skipping network retry")
                                return
                            }
                            self.executeHttpRequest(
                                requestId: requestId,
                                url: url,
                                method: method,
                                headers: headers,
                                body: body,
                                queryParameters: queryParameters,
                                timeout: timeout,
                                multipartFields: multipartFields,
                                multipartFiles: multipartFiles,
                                retries: currentRetries,
                                retriesRemaining: 0 // Не используем retries, но повторяем при сетевой ошибке
                            )
                        }
                        return
                    }
                }
                
                // Проверяем, нужно ли повторить попытку
                if currentRetriesRemaining > 0 {
                    let attempt = currentRetries - currentRetriesRemaining + 1
                    let waitSeconds = min(2 << min(attempt - 1, 8), 512)
                    
                    print("BackgroundHttpClient: Request \(requestId) failed: \(detailedError), retrying in \(waitSeconds) seconds. \(currentRetriesRemaining - 1) retries remaining")
                    
                    self.saveStatus(requestId: requestId, status: 0, error: "Retrying in \(waitSeconds) seconds... (\(currentRetriesRemaining - 1) retries remaining)")
                    
                    // Повторяем попытку после задержки
                    // Примечание: DispatchQueue.asyncAfter работает когда приложение в фоне (свернуто),
                    // но может не работать при полном закрытии приложения.
                    // Для гарантированной работы при закрытом приложении нужно использовать BackgroundTasks framework.
                    DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(waitSeconds)) { [weak self] in
                        guard let self = self else { return }
                        // Проверяем, не отменен ли запрос перед повторной попыткой
                        if self.cancelledRequestIds.contains(requestId) {
                            print("BackgroundHttpClient: Request \(requestId) was cancelled, skipping retry")
                            return
                        }
                        self.executeHttpRequest(
                            requestId: requestId,
                            url: url,
                            method: method,
                            headers: headers,
                            body: body,
                            queryParameters: queryParameters,
                            timeout: timeout,
                            multipartFields: multipartFields,
                            multipartFiles: multipartFiles,
                            retries: currentRetries,
                            retriesRemaining: currentRetriesRemaining - 1
                        )
                    }
                    return
                }
                
                // Если попытки закончились, сохраняем ошибку
                self.saveStatus(requestId: requestId, status: 2, error: detailedError) // 2 = FAILED
                // Очищаем из множества отмененных запросов после окончательной неудачи
                self.cancelledRequestIds.remove(requestId)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                self.saveStatus(requestId: requestId, status: 2, error: "Invalid response: response is not HTTPURLResponse")
                return
            }
            
            // Логируем статус код для отладки
            if httpResponse.statusCode >= 400 {
                print("BackgroundHttpClient: Request \(requestId) failed with status code \(httpResponse.statusCode)")
                print("BackgroundHttpClient: Response headers: \(httpResponse.allHeaderFields)")
            }
            
            // Получаем заголовки
            var responseHeaders: [String: String] = [:]
            for (key, value) in httpResponse.allHeaderFields {
                if let keyString = key as? String, let valueString = value as? String {
                    responseHeaders[keyString] = valueString
                }
            }
            
            // Обрабатываем тело ответа
            var responseBody: String? = nil
            var responseFilePath: String? = nil
            
            if let data = data {
                let contentLength = Int64(data.count)
                let isLargeFile = contentLength > 100 * 1024 // > 100KB
                
                // Сохраняем ответ в файл
                // Примечание: файл будет перезаписан при каждой попытке, но сохраняется в JSON только при финальном результате
                if isLargeFile {
                    // Для больших файлов используем потоковое сохранение
                    responseFilePath = self.saveLargeResponseToFile(requestId: requestId, data: data)
                    responseBody = nil // Для больших файлов не сохраняем в body
                } else {
                    // Для маленьких ответов сохраняем обычным способом
                    responseFilePath = self.saveResponseToFile(requestId: requestId, data: data)
                    
                    // Для маленьких ответов (<10KB) также сохраняем в body для удобства
                    if data.count <= 10000 {
                        responseBody = String(data: data, encoding: .utf8)
                    }
                }
            }
            
            let status: Int = (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) ? 1 : 2 // 1 = COMPLETED, 2 = FAILED
            
            // Если запрос не удался и есть попытки, повторяем
            if status == 2 && currentRetriesRemaining > 0 {
                let attempt = currentRetries - currentRetriesRemaining + 1
                let waitSeconds = min(2 << min(attempt - 1, 8), 512)
                
                print("BackgroundHttpClient: Request \(requestId) failed with status code \(httpResponse.statusCode), retrying in \(waitSeconds) seconds. \(currentRetriesRemaining - 1) retries remaining")
                
                self.saveStatus(requestId: requestId, status: 0, error: "Retrying in \(waitSeconds) seconds... (\(currentRetriesRemaining - 1) retries remaining)")
                
                // Повторяем попытку после задержки
                // Примечание: DispatchQueue.asyncAfter работает когда приложение в фоне (свернуто),
                // но может не работать при полном закрытии приложения.
                // Для гарантированной работы при закрытом приложении нужно использовать BackgroundTasks framework.
                DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(waitSeconds)) { [weak self] in
                    guard let self = self else { return }
                    // Проверяем, не отменен ли запрос перед повторной попыткой
                    if self.cancelledRequestIds.contains(requestId) {
                        print("BackgroundHttpClient: Request \(requestId) was cancelled, skipping retry")
                        return
                    }
                    self.executeHttpRequest(
                        requestId: requestId,
                        url: url,
                        method: method,
                        headers: headers,
                        body: body,
                        queryParameters: queryParameters,
                        timeout: timeout,
                        multipartFields: multipartFields,
                        multipartFiles: multipartFiles,
                        retries: currentRetries,
                        retriesRemaining: currentRetriesRemaining - 1
                    )
                }
                return
            }
            
            // Сохраняем ответ только при финальном результате (когда нет retries или все retries исчерпаны)
            self.saveResponse(
                requestId: requestId,
                statusCode: httpResponse.statusCode,
                headers: responseHeaders,
                body: responseBody,
                responseFilePath: responseFilePath,
                status: status,
                error: status == 2 ? (responseBody ?? "Request failed") : nil
            )
            
            // Обновляем статус
            self.saveStatus(requestId: requestId, status: status)
            
            // Очищаем из множества отмененных запросов после завершения (успешного или неудачного)
            self.cancelledRequestIds.remove(requestId)
        }
        
        activeTasks[requestId] = task
        task.resume()
    }
    
    // MARK: - File Management
    
    private func getStorageDirectory() -> URL {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let storageURL = documentsURL.appendingPathComponent("background_http_client", isDirectory: true)
        
        if !fileManager.fileExists(atPath: storageURL.path) {
            try? fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)
        }
        
        return storageURL
    }
    
    private func saveRequest(
        requestId: String,
        url: String,
        method: String,
        headers: [String: String]?,
        body: String?,
        queryParameters: [String: Any]?,
        timeout: Int,
        multipartFields: [String: String]? = nil,
        multipartFiles: [String: [String: Any]]? = nil
    ) -> (requestId: String, requestFilePath: String) {
        let storageDir = getStorageDirectory()
        let requestsDir = storageDir.appendingPathComponent("requests", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: requestsDir, withIntermediateDirectories: true)
        
        // Если body указан, сохраняем его в отдельный файл
        if let bodyString = body {
            let bodyDir = storageDir.appendingPathComponent("request_bodies", isDirectory: true)
            try? FileManager.default.createDirectory(at: bodyDir, withIntermediateDirectories: true)
            
            let bodyFile = bodyDir.appendingPathComponent("\(requestId).body")
            if let bodyData = bodyString.data(using: .utf8) {
                try? bodyData.write(to: bodyFile)
                // Сохраняем путь к файлу body
                let bodyPathFile = requestsDir.appendingPathComponent("\(requestId).body_path")
                try? bodyFile.path.write(to: bodyPathFile, atomically: true, encoding: .utf8)
                print("BackgroundHttpClient: Request body saved to file: \(bodyFile.path)")
            }
        }
        
        let requestFile = requestsDir.appendingPathComponent("\(requestId).json")
        let requestData: [String: Any] = [
            "url": url,
            "method": method,
            "headers": headers ?? [:],
            "queryParameters": queryParameters ?? [:],
            "timeout": timeout,
            "multipartFields": multipartFields ?? [:],
            "multipartFiles": multipartFiles ?? [:],
            "requestId": requestId
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: requestData) {
            try? jsonData.write(to: requestFile)
        }
        
        return (requestId: requestId, requestFilePath: requestFile.path)
    }
    
    private func getBodyFilePath(requestId: String) -> String? {
        let storageDir = getStorageDirectory()
        let requestsDir = storageDir.appendingPathComponent("requests", isDirectory: true)
        let bodyPathFile = requestsDir.appendingPathComponent("\(requestId).body_path")
        
        guard FileManager.default.fileExists(atPath: bodyPathFile.path),
              let bodyFilePath = try? String(contentsOf: bodyPathFile, encoding: .utf8) else {
            return nil
        }
        
        return bodyFilePath
    }
    
    private func saveResponse(
        requestId: String,
        statusCode: Int,
        headers: [String: String],
        body: String?,
        responseFilePath: String?,
        status: Int,
        error: String?
    ) {
        let storageDir = getStorageDirectory()
        let responsesDir = storageDir.appendingPathComponent("responses", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: responsesDir, withIntermediateDirectories: true)
        
        let responseFile = responsesDir.appendingPathComponent("\(requestId).json")
        let responseData: [String: Any] = [
            "requestId": requestId,
            "statusCode": statusCode,
            "headers": headers,
            "body": body ?? "",
            "responseFilePath": responseFilePath ?? "",
            "status": status,
            "error": error ?? ""
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: responseData) {
            try? jsonData.write(to: responseFile)
        }
    }
    
    private func saveResponseToFile(requestId: String, data: Data) -> String {
        let storageDir = getStorageDirectory()
        let responsesDir = storageDir.appendingPathComponent("responses", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: responsesDir, withIntermediateDirectories: true)
        
        let responseFile = responsesDir.appendingPathComponent("\(requestId)_response.txt")
        try? data.write(to: responseFile)
        
        return responseFile.path
    }
    
    private func saveLargeResponseToFile(requestId: String, data: Data) -> String {
        let storageDir = getStorageDirectory()
        let responsesDir = storageDir.appendingPathComponent("responses", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: responsesDir, withIntermediateDirectories: true)
        
        let responseFile = responsesDir.appendingPathComponent("\(requestId)_response.txt")
        
        // Для больших файлов используем потоковую запись
        // В iOS URLSession.dataTask уже получает данные в памяти,
        // но мы записываем их в файл порциями для оптимизации
        let chunkSize = 1024 * 1024 // 1MB chunks
        var offset = 0
        
        if let fileHandle = try? FileHandle(forWritingTo: responseFile) {
            defer { fileHandle.closeFile() }
            
            while offset < data.count {
                let chunkEnd = min(offset + chunkSize, data.count)
                let chunk = data.subdata(in: offset..<chunkEnd)
                fileHandle.write(chunk)
                offset = chunkEnd
            }
        } else {
            // Fallback: записать все сразу
            try? data.write(to: responseFile)
        }
        
        return responseFile.path
    }
    
    private func saveStatus(requestId: String, status: Int, error: String? = nil) {
        let storageDir = getStorageDirectory()
        let statusDir = storageDir.appendingPathComponent("status", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: statusDir, withIntermediateDirectories: true)
        
        let statusFile = statusDir.appendingPathComponent("\(requestId).json")
        let statusData: [String: Any] = [
            "requestId": requestId,
            "status": status,
            "error": error ?? ""
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: statusData) {
            try? jsonData.write(to: statusFile)
        }
    }
    
    private func loadStatus(requestId: String) -> Int? {
        let storageDir = getStorageDirectory()
        let statusFile = storageDir.appendingPathComponent("status/\(requestId).json")
        
        guard let data = try? Data(contentsOf: statusFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? Int else {
            return nil
        }
        
        return status
    }
    
    private func loadResponse(requestId: String) -> [String: Any]? {
        let storageDir = getStorageDirectory()
        let responseFile = storageDir.appendingPathComponent("responses/\(requestId).json")
        
        guard let data = try? Data(contentsOf: responseFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        return json
    }
    
    /// Удаляет все файлы, связанные с запросом
    private func deleteRequestFiles(requestId: String) {
        let fileManager = FileManager.default
        let storageDir = getStorageDirectory()
        
        // Удаляем файл запроса
        let requestFile = storageDir.appendingPathComponent("requests/\(requestId).json")
        if fileManager.fileExists(atPath: requestFile.path) {
            try? fileManager.removeItem(at: requestFile)
            print("BackgroundHttpClient: Deleted request file: \(requestFile.path)")
        }
        
        // Удаляем файл body_path
        let bodyPathFile = storageDir.appendingPathComponent("requests/\(requestId).body_path")
        if fileManager.fileExists(atPath: bodyPathFile.path) {
            try? fileManager.removeItem(at: bodyPathFile)
            print("BackgroundHttpClient: Deleted body path file: \(bodyPathFile.path)")
        }
        
        // Удаляем файл body (если существует)
        let bodyFile = storageDir.appendingPathComponent("request_bodies/\(requestId).body")
        if fileManager.fileExists(atPath: bodyFile.path) {
            try? fileManager.removeItem(at: bodyFile)
            print("BackgroundHttpClient: Deleted body file: \(bodyFile.path)")
        }
        
        // Удаляем файл ответа JSON
        let responseJsonFile = storageDir.appendingPathComponent("responses/\(requestId).json")
        if fileManager.fileExists(atPath: responseJsonFile.path) {
            try? fileManager.removeItem(at: responseJsonFile)
            print("BackgroundHttpClient: Deleted response JSON file: \(responseJsonFile.path)")
        }
        
        // Удаляем файл ответа (данные)
        let responseDataFile = storageDir.appendingPathComponent("responses/\(requestId)_response.txt")
        if fileManager.fileExists(atPath: responseDataFile.path) {
            try? fileManager.removeItem(at: responseDataFile)
            print("BackgroundHttpClient: Deleted response data file: \(responseDataFile.path)")
        }
        
        // Удаляем файл статуса
        let statusFile = storageDir.appendingPathComponent("status/\(requestId).json")
        if fileManager.fileExists(atPath: statusFile.path) {
            try? fileManager.removeItem(at: statusFile)
            print("BackgroundHttpClient: Deleted status file: \(statusFile.path)")
        }
        
        print("BackgroundHttpClient: All files deleted for request: \(requestId)")
    }
    
}
