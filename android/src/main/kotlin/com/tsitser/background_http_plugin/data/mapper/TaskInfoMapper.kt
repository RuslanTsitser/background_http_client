package com.tsitser.background_http_plugin.data.mapper

import com.tsitser.background_http_plugin.domain.entity.TaskInfo
import java.util.HashMap

/**
 * Mapper для преобразования TaskInfo в Map для Flutter
 */
object TaskInfoMapper {

    /**
     * Преобразует TaskInfo в Map для отправки в Flutter
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

