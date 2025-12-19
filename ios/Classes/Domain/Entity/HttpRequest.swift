import Foundation

/// HTTP request model
struct HttpRequest {
    let url: String
    let method: String
    let headers: [String: String]?
    let body: String?
    let queryParameters: [String: String]?
    let timeout: Int?
    let multipartFields: [String: String]?
    let multipartFiles: [String: MultipartFile]?
    let requestId: String?
    let retries: Int?
    let stuckTimeoutBuffer: Int?
    let queueTimeout: Int?
}

/// Multipart file model
struct MultipartFile {
    let filePath: String
    let filename: String?
    let contentType: String?
}

