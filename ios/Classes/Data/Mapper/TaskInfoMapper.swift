import Foundation

/// Mapper for converting TaskInfo into a Dictionary for Flutter
struct TaskInfoMapper {
    /// Converts TaskInfo into a Dictionary for sending to Flutter
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

