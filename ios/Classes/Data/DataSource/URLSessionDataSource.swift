import Foundation

/// Data source для работы с URLSession и выполнения HTTP запросов
class URLSessionDataSource {
    private var activeTasks: [String: URLSessionDataTask] = [:]
    private var cancelledRequestIds = Set<String>()
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 4 * 60 * 60 // 4 часа для больших файлов
        return URLSession(configuration: config)
    }()
    
    /// Выполняет HTTP запрос
    func executeRequest(
        requestId: String,
        url: URL,
        method: String,
        headers: [String: String]?,
        body: String?,
        queryParameters: [String: String]?,
        timeout: Int,
        multipartFields: [String: String]?,
        multipartFiles: [String: MultipartFile]?,
        retries: Int,
        fileStorage: FileStorageDataSource
    ) async throws {
        // Проверяем, не отменен ли запрос
        if cancelledRequestIds.contains(requestId) {
            return
        }
        
        // Устанавливаем статус IN_PROGRESS с сохранением времени начала
        let currentStatus = fileStorage.loadStatus(requestId: requestId)
        if currentStatus == nil || currentStatus != .inProgress {
            let startTime = Int64(Date().timeIntervalSince1970 * 1000)
            try fileStorage.saveStatus(requestId: requestId, status: .inProgress, startTime: startTime)
        }
        
        var requestURL = url
        
        // Добавляем query параметры
        if let queryParams = queryParameters, !queryParams.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            var queryItems: [URLQueryItem] = []
            for (key, value) in queryParams {
                queryItems.append(URLQueryItem(name: key, value: value))
            }
            components?.queryItems = queryItems
            if let finalURL = components?.url {
                requestURL = finalURL
            }
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.timeoutInterval = TimeInterval(timeout)
        
        // Устанавливаем заголовки
        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Устанавливаем User-Agent, если не указан явно
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue("BackgroundHttpClient/1.0", forHTTPHeaderField: "User-Agent")
        }
        
        // Устанавливаем тело запроса
        let isMultipart = multipartFields != nil || multipartFiles != nil
        
        if isMultipart {
            let (bodyData, boundary) = try buildMultipartBody(
                multipartFields: multipartFields,
                multipartFiles: multipartFiles
            )
            request.httpBody = bodyData
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.setValue("\(bodyData.count)", forHTTPHeaderField: "Content-Length")
        } else if method != "GET" && method != "HEAD", let body = body {
            request.httpBody = body.data(using: .utf8)
            request.setValue("\(request.httpBody?.count ?? 0)", forHTTPHeaderField: "Content-Length")
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }
        
        // Выполняем запрос
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            self.activeTasks.removeValue(forKey: requestId)
            
            if let error = error {
                let errorDescription = "Network error: \(error.localizedDescription)"
                let detailedError: String
                var isNetworkError = false
                
                if let urlError = error as? URLError {
                    detailedError = "URLError code: \(urlError.code.rawValue), description: \(urlError.localizedDescription)"
                    isNetworkError = urlError.code == .notConnectedToInternet ||
                                    urlError.code == .networkConnectionLost ||
                                    urlError.code == .cannotFindHost ||
                                    urlError.code == .cannotConnectToHost ||
                                    urlError.code == .timedOut ||
                                    urlError.code == .dnsLookupFailed
                } else {
                    detailedError = errorDescription
                }
                
                // Проверяем, является ли это ошибкой отсутствия интернета
                let isNoInternetError = (error as? URLError)?.code == .notConnectedToInternet
                
                // Сохраняем ошибку
                try? fileStorage.saveResponse(
                    requestId: requestId,
                    statusCode: 0,
                    headers: [:],
                    body: nil,
                    responseFilePath: nil,
                    status: .failed,
                    error: detailedError
                )
                
                // Не отправляем событие при ошибках - только при успешном завершении
                
                // Если это сетевая ошибка и есть попытки, повторяем
                // НО: при отсутствии интернета не тратим попытки - ждем появления интернета
                if isNetworkError && retries > 0 {
                    if isNoInternetError {
                        // При отсутствии интернета не тратим попытки, просто ждем
                        // Повторяем с теми же retries
                        Task {
                            try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 секунд
                            if !self.cancelledRequestIds.contains(requestId) {
                                try? await self.executeRequest(
                                    requestId: requestId,
                                    url: url,
                                    method: method,
                                    headers: headers,
                                    body: body,
                                    queryParameters: queryParameters,
                                    timeout: timeout,
                                    multipartFields: multipartFields,
                                    multipartFiles: multipartFiles,
                                    retries: retries, // Не уменьшаем retries при отсутствии интернета
                                    fileStorage: fileStorage
                                )
                            }
                        }
                    } else {
                        // При других сетевых ошибках тратим попытки
                        Task {
                            try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 секунд
                            if !self.cancelledRequestIds.contains(requestId) {
                                try? await self.executeRequest(
                                    requestId: requestId,
                                    url: url,
                                    method: method,
                                    headers: headers,
                                    body: body,
                                    queryParameters: queryParameters,
                                    timeout: timeout,
                                    multipartFields: multipartFields,
                                    multipartFiles: multipartFiles,
                                    retries: retries - 1, // Уменьшаем retries при других ошибках
                                    fileStorage: fileStorage
                                )
                            }
                        }
                    }
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                try? fileStorage.saveResponse(
                    requestId: requestId,
                    statusCode: 0,
                    headers: [:],
                    body: nil,
                    responseFilePath: nil,
                    status: .failed,
                    error: "Invalid response: response is not HTTPURLResponse"
                )
                // Не отправляем событие при ошибках - только при успешном завершении
                return
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
                
                if isLargeFile {
                    responseFilePath = self.saveLargeResponseToFile(requestId: requestId, data: data)
                    responseBody = nil
                } else {
                    responseFilePath = self.saveResponseToFile(requestId: requestId, data: data)
                    if data.count <= 10000 {
                        responseBody = String(data: data, encoding: .utf8)
                    }
                }
            }
            
            let status: RequestStatus = (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) ? .completed : .failed
            
            // Сохраняем ответ
            try? fileStorage.saveResponse(
                requestId: requestId,
                statusCode: httpResponse.statusCode,
                headers: responseHeaders,
                body: responseBody,
                responseFilePath: responseFilePath,
                status: status,
                error: status == .failed ? (responseBody ?? "Request failed") : nil
            )
            
            // Отправляем событие только при успешном завершении
            if status == .completed {
                TaskCompletedEventStreamHandler.shared.sendCompletedTask(requestId: requestId)
            }
            
            // Очищаем из множества отмененных запросов
            self.cancelledRequestIds.remove(requestId)
        }
        
        activeTasks[requestId] = task
        task.resume()
    }
    
    /// Отменяет задачу
    func cancelTask(requestId: String) {
        cancelledRequestIds.insert(requestId)
        if let task = activeTasks[requestId] {
            task.cancel()
            activeTasks.removeValue(forKey: requestId)
        }
    }
    
    /// Удаляет задачу
    func deleteTask(requestId: String) {
        cancelTask(requestId: requestId)
    }
    
    private func buildMultipartBody(
        multipartFields: [String: String]?,
        multipartFiles: [String: MultipartFile]?
    ) throws -> (Data, String) {
        let boundary = "----WebKitFormBoundary\(UUID().uuidString)"
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
        multipartFiles?.forEach { fieldName, file in
            guard FileManager.default.fileExists(atPath: file.filePath),
                  let fileData = try? Data(contentsOf: URL(fileURLWithPath: file.filePath)) else {
                return
            }
            
            let filename = file.filename ?? URL(fileURLWithPath: file.filePath).lastPathComponent
            let contentType = file.contentType ?? "application/octet-stream"
            
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
        
        return (bodyData, boundary)
    }
    
    private func saveResponseToFile(requestId: String, data: Data) -> String {
        let responsesDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("background_http_client/responses", isDirectory: true)
        try? FileManager.default.createDirectory(at: responsesDir, withIntermediateDirectories: true)
        
        let responseFile = responsesDir.appendingPathComponent("\(requestId)_response.txt")
        try? data.write(to: responseFile)
        
        return responseFile.path
    }
    
    private func saveLargeResponseToFile(requestId: String, data: Data) -> String {
        return saveResponseToFile(requestId: requestId, data: data)
    }
    
    /// Проверяет, находится ли задача в ожидании
    func isTaskPending(requestId: String) -> Bool {
        return activeTasks[requestId] != nil
    }
    
    /// Отменяет все задачи
    /// Возвращает количество отмененных задач
    func cancelAllTasks() -> Int {
        let count = activeTasks.count
        for (requestId, task) in activeTasks {
            task.cancel()
            cancelledRequestIds.insert(requestId)
        }
        activeTasks.removeAll()
        return count
    }
}

