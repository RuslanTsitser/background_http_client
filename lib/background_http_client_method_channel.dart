import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'background_http_client_platform_interface.dart';

/// [BackgroundHttpClientPlatform] implementation using method channels
class MethodChannelBackgroundHttpClient extends BackgroundHttpClientPlatform {
  /// Method channel for interaction with the native platform
  @visibleForTesting
  final methodChannel = const MethodChannel('background_http_client');

  /// Event channel for receiving events about completed tasks
  @visibleForTesting
  final eventChannel =
      const EventChannel('background_http_client/task_completed');

  @override
  Future<Map<String, dynamic>> createRequest(
      Map<String, dynamic> requestJson) async {
    final result = await methodChannel.invokeMethod<Map<Object?, Object?>>(
      'createRequest',
      requestJson,
    );
    if (result == null) {
      throw PlatformException(
        code: 'CREATE_REQUEST_FAILED',
        message: 'Failed to create request',
      );
    }
    return Map<String, dynamic>.from(result);
  }

  @override
  Future<Map<String, dynamic>?> getRequestStatus(String requestId) async {
    try {
      final result = await methodChannel.invokeMethod<Map<Object?, Object?>>(
        'getRequestStatus',
        {'requestId': requestId},
      );
      if (result == null) {
        return null;
      }
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      // If the task is not found, return null instead of throwing an error
      if (e.code == 'NOT_FOUND') {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>?> getResponse(String requestId) async {
    try {
      final result = await methodChannel.invokeMethod<Map<Object?, Object?>>(
        'getResponse',
        {'requestId': requestId},
      );
      if (result == null) {
        return null;
      }
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      // If the task is not found, return null instead of throwing an error
      if (e.code == 'NOT_FOUND') {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<bool?> cancelRequest(String requestId) async {
    try {
      final result = await methodChannel.invokeMethod<bool>(
        'cancelRequest',
        {'requestId': requestId},
      );
      return result;
    } on PlatformException catch (e) {
      // If the task is not found, return null
      if (e.code == 'NOT_FOUND') {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<bool?> deleteRequest(String requestId) async {
    try {
      final result = await methodChannel.invokeMethod<bool>(
        'deleteRequest',
        {'requestId': requestId},
      );
      return result;
    } on PlatformException catch (e) {
      // If the task is not found, return null
      if (e.code == 'NOT_FOUND') {
        return null;
      }
      rethrow;
    }
  }

  @override
  Stream<String> getCompletedTasksStream() {
    return eventChannel.receiveBroadcastStream().cast<String>();
  }

  @override
  Future<List<Map<String, dynamic>>> getPendingTasks() async {
    try {
      final result =
          await methodChannel.invokeMethod<List<Object?>>('getPendingTasks');
      if (result == null) {
        return [];
      }
      return result
          .map((item) =>
              Map<String, dynamic>.from(item as Map<Object?, Object?>))
          .toList();
    } on PlatformException catch (e) {
      throw PlatformException(
        code: e.code,
        message: e.message,
        details: e.details,
      );
    }
  }

  @override
  Future<int> cancelAllTasks() async {
    try {
      final result = await methodChannel.invokeMethod<int>('cancelAllTasks');
      return result ?? 0;
    } on PlatformException catch (e) {
      throw PlatformException(
        code: e.code,
        message: e.message,
        details: e.details,
      );
    }
  }

  @override
  Future<Map<String, dynamic>> getQueueStats() async {
    try {
      final result = await methodChannel
          .invokeMethod<Map<Object?, Object?>>('getQueueStats');
      if (result == null) {
        return {
          'pendingCount': 0,
          'activeCount': 0,
          'maxConcurrent': 30,
          'maxQueueSize': 10000,
        };
      }
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      throw PlatformException(
        code: e.code,
        message: e.message,
        details: e.details,
      );
    }
  }

  @override
  Future<bool> setMaxConcurrentTasks(int count) async {
    try {
      final result = await methodChannel.invokeMethod<bool>(
        'setMaxConcurrentTasks',
        {'count': count},
      );
      return result ?? false;
    } on PlatformException catch (e) {
      throw PlatformException(
        code: e.code,
        message: e.message,
        details: e.details,
      );
    }
  }

  @override
  Future<bool> setMaxQueueSize(int size) async {
    try {
      final result = await methodChannel.invokeMethod<bool>(
        'setMaxQueueSize',
        {'size': size},
      );
      return result ?? false;
    } on PlatformException catch (e) {
      throw PlatformException(
        code: e.code,
        message: e.message,
        details: e.details,
      );
    }
  }

  @override
  Future<bool> syncQueueState() async {
    try {
      final result = await methodChannel.invokeMethod<bool>('syncQueueState');
      return result ?? false;
    } on PlatformException catch (e) {
      throw PlatformException(
        code: e.code,
        message: e.message,
        details: e.details,
      );
    }
  }

  @override
  Future<bool> processQueue() async {
    try {
      final result = await methodChannel.invokeMethod<bool>('processQueue');
      return result ?? false;
    } on PlatformException catch (e) {
      throw PlatformException(
        code: e.code,
        message: e.message,
        details: e.details,
      );
    }
  }
}
