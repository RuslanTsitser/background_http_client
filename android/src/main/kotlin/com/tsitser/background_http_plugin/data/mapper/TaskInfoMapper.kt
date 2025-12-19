package com.tsitser.background_http_plugin.data.mapper

import com.tsitser.background_http_plugin.domain.entity.TaskInfo
import java.util.HashMap

/**
 * Mapper for converting TaskInfo into a Map for Flutter.
 */
object TaskInfoMapper {

    /**
     * Converts TaskInfo into a Map for sending to Flutter.
     */
    fun toFlutterMap(taskInfo: TaskInfo): Map<String, Any> {
        val map = HashMap<String, Any>()
        map["id"] = taskInfo.id
        map["status"] = taskInfo.status.value
        map["path"] = taskInfo.path
        map["registrationDate"] = taskInfo.registrationDate
        taskInfo.responseJson?.let {
            map["responseJson"] = it
        }
        return map
    }
}

