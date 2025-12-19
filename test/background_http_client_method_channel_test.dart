import 'package:background_http_client/background_http_client_method_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelBackgroundHttpClient platform = MethodChannelBackgroundHttpClient();
  const MethodChannel channel = MethodChannel('background_http_client');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        switch (methodCall.method) {
          case 'createRequest':
            return {
              'id': 'test-id',
              'status': 0, // RequestStatus.inProgress
              'path': '/test/path',
              'registrationDate': DateTime.now().millisecondsSinceEpoch,
            };
          case 'getRequestStatus':
            return {
              'id': 'test-id',
              'status': 0, // RequestStatus.inProgress
              'path': '/test/path',
              'registrationDate': DateTime.now().millisecondsSinceEpoch,
            };
          case 'getResponse':
            return {
              'id': 'test-id',
              'status': 1, // RequestStatus.completed
              'path': '/test/path',
              'registrationDate': DateTime.now().millisecondsSinceEpoch,
              'responseJson': {
                'requestId': 'test-id',
                'statusCode': 200,
                'headers': {},
                'status': 1, // RequestStatus.completed
              },
            };
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('createRequest', () async {
    final result = await platform.createRequest({
      'url': 'https://example.com',
      'method': 'GET',
    });
    expect(result['id'], 'test-id');
    expect(result['path'], '/test/path');
  });

  test('getRequestStatus', () async {
    final status = await platform.getRequestStatus('test-id');
    expect(status, isNotNull);
    expect(status?['status'], 0);
  });

  test('getRequestStatus returns null when request not found', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        if (methodCall.method == 'getRequestStatus') {
          // Simulate PlatformException with NOT_FOUND code
          throw PlatformException(
            code: 'NOT_FOUND',
            message: 'Request not found',
          );
        }
        return null;
      },
    );

    final status = await platform.getRequestStatus('non-existent-id');
    expect(status, isNull);
  });

  test('getResponse', () async {
    final response = await platform.getResponse('test-id');
    expect(response, isNotNull);
    expect(response?['id'], 'test-id');
    expect(response?['responseJson']?['statusCode'], 200);
  });
}
