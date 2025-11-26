import Foundation

/// Data source для работы с файловым хранилищем
class FileStorageDataSource {
    private let storageDir: URL
    
    init() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storageDir = documentsURL.appendingPathComponent("background_http_client", isDirectory: true)
        
        // Создаем директории если их нет
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: requestsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: responsesDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: statusDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: bodiesDir, withIntermediateDirectories: true)
    }
    
    private var requestsDir: URL {
        storageDir.appendingPathComponent("requests", isDirectory: true)
    }
    
    private var responsesDir: URL {
        storageDir.appendingPathComponent("responses", isDirectory: true)
    }
    
    private var statusDir: URL {
        storageDir.appendingPathComponent("status", isDirectory: true)
    }
    
    private var bodiesDir: URL {
        storageDir.appendingPathComponent("request_bodies", isDirectory: true)
    }
    
    /// Сохраняет запрос в файл и возвращает информацию о задаче
    func saveRequest(request: HttpRequest, requestId: String, registrationDate: Int64) throws -> TaskInfo {
        // Сохраняем body в отдельный файл, если он есть
        if let body = request.body, let bodyData = body.data(using: .utf8) {
            let bodyFile = bodiesDir.appendingPathComponent("\(requestId).body")
            try bodyData.write(to: bodyFile)
        }
        
        // Сохраняем запрос в JSON
        let requestFile = requestsDir.appendingPathComponent("\(requestId).json")
        let requestData: [String: Any] = [
            "url": request.url,
            "method": request.method,
            "headers": request.headers ?? [:],
            "body": request.body ?? "",
            "queryParameters": request.queryParameters ?? [:],
            "timeout": request.timeout ?? 120,
            "multipartFields": request.multipartFields ?? [:],
            "multipartFiles": request.multipartFiles?.mapValues { file in
                [
                    "filePath": file.filePath,
                    "filename": file.filename ?? "",
                    "contentType": file.contentType ?? ""
                ]
            } ?? [:],
            "requestId": requestId,
            "retries": request.retries ?? 0,
            "stuckTimeoutBuffer": request.stuckTimeoutBuffer ?? 60,
            "queueTimeout": request.queueTimeout ?? 600
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestData)
        try jsonData.write(to: requestFile)
        
        // Сохраняем начальный статус
        try saveStatus(requestId: requestId, status: .inProgress, startTime: registrationDate)
        
        return TaskInfo(
            id: requestId,
            status: .inProgress,
            path: requestFile.path,
            registrationDate: registrationDate,
            responseJson: nil
        )
    }
    
    /// Загружает информацию о задаче
    func loadTaskInfo(requestId: String) -> TaskInfo? {
        let requestFile = requestsDir.appendingPathComponent("\(requestId).json")
        guard FileManager.default.fileExists(atPath: requestFile.path) else {
            return nil
        }
        
        let status = loadStatus(requestId: requestId) ?? .inProgress
        // Получаем дату регистрации из файла статуса, если она там есть, иначе используем lastModified
        let registrationDate = loadRegistrationDate(requestId: requestId) ?? {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: requestFile.path),
               let modificationDate = attributes[.modificationDate] as? Date {
                return Int64(modificationDate.timeIntervalSince1970 * 1000)
            } else {
                return Int64(Date().timeIntervalSince1970 * 1000)
            }
        }()
        
        return TaskInfo(
            id: requestId,
            status: status,
            path: requestFile.path,
            registrationDate: registrationDate,
            responseJson: nil
        )
    }
    
    /// Загружает дату регистрации из файла статуса
    private func loadRegistrationDate(requestId: String) -> Int64? {
        let statusFile = statusDir.appendingPathComponent("\(requestId).json")
        guard FileManager.default.fileExists(atPath: statusFile.path),
              let data = try? Data(contentsOf: statusFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let startTime = json["startTime"] as? Int64 else {
            return nil
        }
        return startTime
    }
    
    /// Загружает ответ задачи
    func loadTaskResponse(requestId: String) -> TaskInfo? {
        guard var taskInfo = loadTaskInfo(requestId: requestId) else {
            return nil
        }
        
        let responseFile = responsesDir.appendingPathComponent("\(requestId).json")
        guard FileManager.default.fileExists(atPath: responseFile.path) else {
            return taskInfo
        }
        
        if let data = try? Data(contentsOf: responseFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return TaskInfo(
                id: taskInfo.id,
                status: taskInfo.status,
                path: taskInfo.path,
                registrationDate: taskInfo.registrationDate,
                responseJson: json
            )
        }
        
        return taskInfo
    }
    
    /// Сохраняет статус задачи
    func saveStatus(requestId: String, status: RequestStatus, startTime: Int64? = nil) throws {
        let statusFile = statusDir.appendingPathComponent("\(requestId).json")
        var statusData: [String: Any] = [
            "requestId": requestId,
            "status": status.rawValue
        ]
        
        if let startTime = startTime {
            statusData["startTime"] = startTime
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: statusData)
        try jsonData.write(to: statusFile)
    }
    
    /// Загружает статус задачи
    func loadStatus(requestId: String) -> RequestStatus? {
        let statusFile = statusDir.appendingPathComponent("\(requestId).json")
        guard FileManager.default.fileExists(atPath: statusFile.path),
              let data = try? Data(contentsOf: statusFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let statusValue = json["status"] as? Int,
              let status = RequestStatus(rawValue: statusValue) else {
            return nil
        }
        
        return status
    }
    
    /// Сохраняет ответ от сервера
    func saveResponse(
        requestId: String,
        statusCode: Int,
        headers: [String: String],
        body: String?,
        responseFilePath: String?,
        status: RequestStatus,
        error: String?
    ) throws {
        let responseFile = responsesDir.appendingPathComponent("\(requestId).json")
        let responseData: [String: Any] = [
            "requestId": requestId,
            "statusCode": statusCode,
            "headers": headers,
            "body": body ?? "",
            "responseFilePath": responseFilePath ?? "",
            "status": status.rawValue,
            "error": error ?? ""
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: responseData)
        try jsonData.write(to: responseFile)
        
        // Обновляем статус
        try saveStatus(requestId: requestId, status: status)
    }
    
    /// Удаляет все файлы, связанные с задачей
    func deleteTaskFiles(requestId: String) -> Bool {
        var deleted = true
        
        // Удаляем файл запроса
        let requestFile = requestsDir.appendingPathComponent("\(requestId).json")
        if FileManager.default.fileExists(atPath: requestFile.path) {
            try? FileManager.default.removeItem(at: requestFile)
        } else {
            deleted = false
        }
        
        // Удаляем файл body
        let bodyFile = bodiesDir.appendingPathComponent("\(requestId).body")
        try? FileManager.default.removeItem(at: bodyFile)
        
        // Удаляем файл ответа JSON
        let responseJsonFile = responsesDir.appendingPathComponent("\(requestId).json")
        try? FileManager.default.removeItem(at: responseJsonFile)
        
        // Удаляем файл ответа (данные)
        let responseDataFile = responsesDir.appendingPathComponent("\(requestId)_response.txt")
        try? FileManager.default.removeItem(at: responseDataFile)
        
        // Удаляем файл статуса
        let statusFile = statusDir.appendingPathComponent("\(requestId).json")
        try? FileManager.default.removeItem(at: statusFile)
        
        return deleted
    }
    
    /// Проверяет существование задачи
    func taskExists(requestId: String) -> Bool {
        let requestFile = requestsDir.appendingPathComponent("\(requestId).json")
        return FileManager.default.fileExists(atPath: requestFile.path)
    }
    
    /// Получает список всех ID задач из файловой системы
    func getAllTaskIds() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: requestsDir, includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
    }
}

