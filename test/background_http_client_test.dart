import 'package:background_http_client/background_http_client.dart';
import 'package:background_http_client/background_http_client_method_channel.dart';
import 'package:background_http_client/background_http_client_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockBackgroundHttpClientPlatform with MockPlatformInterfaceMixin implements BackgroundHttpClientPlatform {
  @override
  Future<Map<String, dynamic>> createRequest(Map<String, dynamic> requestJson) async {
    return {
      'id': 'test-request-id',
      'status': RequestStatus.completed.index,
      'path': '/path/to/request/file',
      'registrationDate': DateTime.now().millisecondsSinceEpoch,
    };
  }

  @override
  Future<Map<String, dynamic>?> getRequestStatus(String requestId) async {
    return {
      'id': requestId,
      'status': RequestStatus.completed.index,
      'path': '/path/to/request/file',
      'registrationDate': DateTime.now().millisecondsSinceEpoch,
    };
  }

  @override
  Future<Map<String, Map<String, dynamic>?>> getBatchRequestStatus(
      List<String> requestIds) async {
    final Map<String, Map<String, dynamic>?> result = {};
    for (final requestId in requestIds) {
      result[requestId] = {
        'id': requestId,
        'status': RequestStatus.completed.index,
        'path': '/path/to/request/file',
        'registrationDate': DateTime.now().millisecondsSinceEpoch,
      };
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>?> getResponse(String requestId) async {
    return {
      'id': requestId,
      'status': RequestStatus.completed.index,
      'path': '/path/to/request/file',
      'registrationDate': DateTime.now().millisecondsSinceEpoch,
      'responseJson': {
        'requestId': requestId,
        'statusCode': 200,
        'headers': {},
        'status': RequestStatus.completed.index,
        'responseFilePath': '/path/to/response/file',
      },
    };
  }

  @override
  Future<bool?> cancelRequest(String requestId) async {
    return true;
  }

  @override
  Future<bool?> deleteRequest(String requestId) async {
    return true;
  }

  @override
  Stream<String> getCompletedTasksStream() {
    return const Stream.empty();
  }

  @override
  Future<List<Map<String, dynamic>>> getPendingTasks() async {
    return [];
  }

  @override
  Future<int> cancelAllTasks() async {
    return 0;
  }

  @override
  Future<Map<String, dynamic>> getQueueStats() async {
    return {
      'pendingCount': 0,
      'activeCount': 0,
      'maxConcurrent': 30,
      'maxQueueSize': 10000,
    };
  }

  @override
  Future<bool> setMaxConcurrentTasks(int count) async {
    return true;
  }

  @override
  Future<bool> setMaxQueueSize(int size) async {
    return true;
  }

  @override
  Future<bool> syncQueueState() async {
    return true;
  }

  @override
  Future<bool> processQueue() async {
    return true;
  }
}

class MockBackgroundHttpClientPlatformForNullStatus
    with MockPlatformInterfaceMixin
    implements BackgroundHttpClientPlatform {
  @override
  Future<Map<String, dynamic>> createRequest(Map<String, dynamic> requestJson) async {
    return {
      'id': 'test-request-id',
      'status': RequestStatus.inProgress.index,
      'path': '/path/to/request/file',
      'registrationDate': DateTime.now().millisecondsSinceEpoch,
    };
  }

  @override
  Future<Map<String, dynamic>?> getRequestStatus(String requestId) async {
    return null;
  }

  @override
  Future<Map<String, Map<String, dynamic>?>> getBatchRequestStatus(
      List<String> requestIds) async {
    final Map<String, Map<String, dynamic>?> result = {};
    for (final requestId in requestIds) {
      result[requestId] = null;
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>?> getResponse(String requestId) async {
    return null;
  }

  @override
  Future<bool?> cancelRequest(String requestId) async {
    return null;
  }

  @override
  Future<bool?> deleteRequest(String requestId) async {
    return null;
  }

  @override
  Stream<String> getCompletedTasksStream() {
    return const Stream.empty();
  }

  @override
  Future<List<Map<String, dynamic>>> getPendingTasks() async {
    return [];
  }

  @override
  Future<int> cancelAllTasks() async {
    return 0;
  }

  @override
  Future<Map<String, dynamic>> getQueueStats() async {
    return {
      'pendingCount': 0,
      'activeCount': 0,
      'maxConcurrent': 30,
      'maxQueueSize': 10000,
    };
  }

  @override
  Future<bool> setMaxConcurrentTasks(int count) async {
    return true;
  }

  @override
  Future<bool> setMaxQueueSize(int size) async {
    return true;
  }

  @override
  Future<bool> syncQueueState() async {
    return true;
  }

  @override
  Future<bool> processQueue() async {
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final BackgroundHttpClientPlatform initialPlatform = BackgroundHttpClientPlatform.instance;

  test('$MethodChannelBackgroundHttpClient is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelBackgroundHttpClient>());
  });

  test('get returns TaskInfo', () async {
    final mockPlatform = MockBackgroundHttpClientPlatform();
    BackgroundHttpClientPlatform.instance = mockPlatform;
    final client = BackgroundHttpClient();

    final taskInfo = await client.get('https://example.com');
    expect(taskInfo.id, 'test-request-id');
    expect(taskInfo.path, '/path/to/request/file');
  });

  test('getRequestStatus returns TaskInfo', () async {
    final mockPlatform = MockBackgroundHttpClientPlatform();
    BackgroundHttpClientPlatform.instance = mockPlatform;
    final client = BackgroundHttpClient();

    final taskInfo = await client.getRequestStatus('test-id');
    expect(taskInfo, isNotNull);
    expect(taskInfo?.statusEnum, RequestStatus.completed);
  });

  test('getRequestStatus returns null when request not found', () async {
    final mockPlatform = MockBackgroundHttpClientPlatformForNullStatus();
    BackgroundHttpClientPlatform.instance = mockPlatform;
    final client = BackgroundHttpClient();

    final status = await client.getRequestStatus('non-existent-id');
    expect(status, isNull);
  });

  test('getResponse returns TaskInfo with responseJson', () async {
    final mockPlatform = MockBackgroundHttpClientPlatform();
    BackgroundHttpClientPlatform.instance = mockPlatform;
    final client = BackgroundHttpClient();

    final taskInfo = await client.getResponse('test-id');
    expect(taskInfo, isNotNull);
    expect(taskInfo?.responseJson, isNotNull);
    expect(taskInfo?.responseJson?['statusCode'], 200);
    expect(taskInfo?.responseJson?['responseFilePath'], '/path/to/response/file');
  });
}
