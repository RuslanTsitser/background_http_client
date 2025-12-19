import Foundation

/// Mapper for converting between domain and data models
struct RequestMapper {
    /// Converts a Dictionary from Flutter into an HttpRequest domain entity
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
    
    /// Generates a unique ID for a request
    static func generateRequestId() -> String {
        return UUID().uuidString
    }
}

