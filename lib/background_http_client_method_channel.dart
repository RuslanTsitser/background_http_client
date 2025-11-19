import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'background_http_client_platform_interface.dart';

/// Реализация [BackgroundHttpClientPlatform] используя method channels
class MethodChannelBackgroundHttpClient
    extends BackgroundHttpClientPlatform {
  /// Method channel для взаимодействия с нативной платформой
  @visibleForTesting
  final methodChannel = const MethodChannel('background_http_client');

  @override
  Future<Map<String, dynamic>> executeRequest(
      Map<String, dynamic> requestJson) async {
    final result = await methodChannel.invokeMethod<Map<Object?, Object?>>(
      'executeRequest',
      requestJson,
    );
    if (result == null) {
      throw PlatformException(
        code: 'EXECUTE_REQUEST_FAILED',
        message: 'Failed to execute request',
      );
    }
    return Map<String, dynamic>.from(result);
  }

  @override
  Future<int> getRequestStatus(String requestId) async {
    final result = await methodChannel.invokeMethod<int>(
      'getRequestStatus',
      {'requestId': requestId},
    );
    if (result == null) {
      throw PlatformException(
        code: 'GET_STATUS_FAILED',
        message: 'Failed to get request status',
      );
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>?> getResponse(String requestId) async {
    final result = await methodChannel.invokeMethod<Map<Object?, Object?>>(
      'getResponse',
      {'requestId': requestId},
    );
    if (result == null) {
      return null;
    }
    return Map<String, dynamic>.from(result);
  }

  @override
  Future<void> cancelRequest(String requestId) async {
    await methodChannel.invokeMethod<void>(
      'cancelRequest',
      {'requestId': requestId},
    );
  }

  @override
  Future<void> deleteRequest(String requestId) async {
    await methodChannel.invokeMethod<void>(
      'deleteRequest',
      {'requestId': requestId},
    );
  }
}
