import 'package:flutter_test/flutter_test.dart';
import 'package:background_http_client/background_http_client.dart';
import 'package:background_http_client/background_http_client_platform_interface.dart';
import 'package:background_http_client/background_http_client_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockBackgroundHttpClientPlatform
    with MockPlatformInterfaceMixin
    implements BackgroundHttpClientPlatform {
  @override
  Future<Map<String, dynamic>> executeRequest(
      Map<String, dynamic> requestJson) async {
    return {
      'requestId': 'test-request-id',
      'requestFilePath': '/path/to/request/file',
    };
  }

  @override
  Future<int?> getRequestStatus(String requestId) async {
    return RequestStatus.completed.index;
  }

  @override
  Future<Map<String, dynamic>?> getResponse(String requestId) async {
    return {
      'requestId': requestId,
      'statusCode': 200,
      'headers': {},
      'status': RequestStatus.completed.index,
      'responseFilePath': '/path/to/response/file',
    };
  }

  @override
  Future<void> cancelRequest(String requestId) async {
    // Mock implementation
  }

  @override
  Future<void> deleteRequest(String requestId) async {
    // Mock implementation
  }
}

class MockBackgroundHttpClientPlatformForNullStatus
    with MockPlatformInterfaceMixin
    implements BackgroundHttpClientPlatform {
  @override
  Future<Map<String, dynamic>> executeRequest(
      Map<String, dynamic> requestJson) async {
    return {
      'requestId': 'test-request-id',
      'requestFilePath': '/path/to/request/file',
    };
  }

  @override
  Future<int?> getRequestStatus(String requestId) async {
    return null;
  }

  @override
  Future<Map<String, dynamic>?> getResponse(String requestId) async {
    return null;
  }

  @override
  Future<void> cancelRequest(String requestId) async {
    // Mock implementation
  }

  @override
  Future<void> deleteRequest(String requestId) async {
    // Mock implementation
  }
}

void main() {
  final BackgroundHttpClientPlatform initialPlatform =
      BackgroundHttpClientPlatform.instance;

  test('$MethodChannelBackgroundHttpClient is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelBackgroundHttpClient>());
  });

  test('executeRequest returns RequestInfo', () async {
    final client = BackgroundHttpClient();
    final mockPlatform = MockBackgroundHttpClientPlatform();
    BackgroundHttpClientPlatform.instance = mockPlatform;

    final requestInfo = await client.get('https://example.com');
    expect(requestInfo.requestId, 'test-request-id');
    expect(requestInfo.requestFilePath, '/path/to/request/file');
  });

  test('getRequestStatus returns status', () async {
    final client = BackgroundHttpClient();
    final mockPlatform = MockBackgroundHttpClientPlatform();
    BackgroundHttpClientPlatform.instance = mockPlatform;

    final status = await client.getRequestStatus('test-id');
    expect(status, RequestStatus.completed);
  });

  test('getRequestStatus returns null when request not found', () async {
    final client = BackgroundHttpClient();
    final mockPlatform = MockBackgroundHttpClientPlatformForNullStatus();
    BackgroundHttpClientPlatform.instance = mockPlatform;

    final status = await client.getRequestStatus('non-existent-id');
    expect(status, isNull);
  });

  test('getResponse returns HttpResponse', () async {
    final client = BackgroundHttpClient();
    final mockPlatform = MockBackgroundHttpClientPlatform();
    BackgroundHttpClientPlatform.instance = mockPlatform;

    final response = await client.getResponse('test-id');
    expect(response, isNotNull);
    expect(response?.statusCode, 200);
    expect(response?.status, RequestStatus.completed);
    expect(response?.responseFilePath, '/path/to/response/file');
  });
}
