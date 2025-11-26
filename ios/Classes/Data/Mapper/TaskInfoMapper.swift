import Foundation

/// Mapper для преобразования TaskInfo в Dictionary для Flutter
struct TaskInfoMapper {
    /// Преобразует TaskInfo в Dictionary для отправки в Flutter
    static func toFlutterMap(_ taskInfo: TaskInfo) -> [String: Any] {
        var map: [String: Any] = [
            "id": taskInfo.id,
            "status": taskInfo.status.rawValue,
            "path": taskInfo.path,
            "registrationDate": taskInfo.registrationDate
        ]
        
        if let responseJson = taskInfo.responseJson {
            map["responseJson"] = responseJson
        }
        
        return map
    }
}

