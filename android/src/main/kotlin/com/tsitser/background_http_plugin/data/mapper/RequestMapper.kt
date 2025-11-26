package com.tsitser.background_http_plugin.data.mapper

import com.tsitser.background_http_plugin.domain.entity.HttpRequest
import com.tsitser.background_http_plugin.domain.entity.MultipartFile
import java.util.UUID

/**
 * Mapper для преобразования между domain и data моделями
 */
object RequestMapper {

    /**
     * Преобразует Map из Flutter в HttpRequest domain entity
     */
    fun fromFlutterMap(map: Map<*, *>): HttpRequest {
        @Suppress("UNCHECKED_CAST")
        val headersMap = (map["headers"] as? Map<*, *>)?.let { map ->
            map.filterKeys { it is String }
                .filterValues { it is String }
                .mapKeys { it.key as String }
                .mapValues { it.value as String }
                .takeIf { it.isNotEmpty() }
        }

        @Suppress("UNCHECKED_CAST")
        val queryParamsMap = (map["queryParameters"] as? Map<*, *>)?.let { map ->
            map.filterKeys { it is String }
                .mapKeys { it.key as String }
                .mapValues { it.value.toString() }
                .takeIf { it.isNotEmpty() }
        }

        @Suppress("UNCHECKED_CAST")
        val multipartFieldsMap = (map["multipartFields"] as? Map<*, *>)?.let { map ->
            map.filterKeys { it is String }
                .filterValues { it is String }
                .mapKeys { it.key as String }
                .mapValues { it.value as String }
                .takeIf { it.isNotEmpty() }
        }

        @Suppress("UNCHECKED_CAST")
        val multipartFilesMap = (map["multipartFiles"] as? Map<*, *>)?.let { filesMap ->
            val result = mutableMapOf<String, MultipartFile>()
            filesMap.forEach { (key, value) ->
                if (key is String && value is Map<*, *>) {
                    try {
                        @Suppress("UNCHECKED_CAST")
                        val fileMap = value as Map<String, Any>
                        val filePath = fileMap["filePath"] as? String
                        if (filePath != null) {
                            result[key] = MultipartFile(
                                filePath = filePath,
                                filename = fileMap["filename"] as? String,
                                contentType = fileMap["contentType"] as? String
                            )
                        }
                    } catch (e: Exception) {
                        android.util.Log.e("RequestMapper", "Error parsing file for key: $key", e)
                    }
                }
            }
            result.takeIf { it.isNotEmpty() }
        }

        return HttpRequest(
            url = map["url"] as String,
            method = map["method"] as String,
            headers = headersMap,
            body = map["body"] as? String,
            queryParameters = queryParamsMap,
            timeout = (map["timeout"] as? Number)?.toInt(),
            multipartFields = multipartFieldsMap,
            multipartFiles = multipartFilesMap,
            requestId = map["requestId"] as? String,
            retries = (map["retries"] as? Number)?.toInt(),
            stuckTimeoutBuffer = (map["stuckTimeoutBuffer"] as? Number)?.toInt(),
            queueTimeout = (map["queueTimeout"] as? Number)?.toInt()
        )
    }

    /**
     * Генерирует уникальный ID для запроса
     */
    fun generateRequestId(): String {
        return UUID.randomUUID().toString()
    }
}

