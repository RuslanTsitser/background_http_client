import Foundation

/// Mapper для преобразования между domain и data моделями
struct RequestMapper {
    /// Преобразует Dictionary из Flutter в HttpRequest domain entity
    static func fromFlutterMap(_ map: [String: Any]) -> HttpRequest {
        let headers = map["headers"] as? [String: String]
        
        let queryParameters = (map["queryParameters"] as? [String: Any])?.mapValues { "\($0)" }
        
        let multipartFields = map["multipartFields"] as? [String: String]
        
        let multipartFiles = (map["multipartFiles"] as? [String: [String: Any]])?.mapValues { fileMap in
            MultipartFile(
                filePath: fileMap["filePath"] as? String ?? "",
                filename: fileMap["filename"] as? String,
                contentType: fileMap["contentType"] as? String
            )
        }
        
        return HttpRequest(
            url: map["url"] as! String,
            method: map["method"] as! String,
            headers: headers,
            body: map["body"] as? String,
            queryParameters: queryParameters,
            timeout: map["timeout"] as? Int,
            multipartFields: multipartFields,
            multipartFiles: multipartFiles,
            requestId: map["requestId"] as? String,
            retries: map["retries"] as? Int,
            stuckTimeoutBuffer: map["stuckTimeoutBuffer"] as? Int,
            queueTimeout: map["queueTimeout"] as? Int
        )
    }
    
    /// Генерирует уникальный ID для запроса
    static func generateRequestId() -> String {
        return UUID().uuidString
    }
}

