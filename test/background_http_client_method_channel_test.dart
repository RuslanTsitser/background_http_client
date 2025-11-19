import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:background_http_client/background_http_client_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelBackgroundHttpClient platform =
      MethodChannelBackgroundHttpClient();
  const MethodChannel channel = MethodChannel('background_http_client');

  setUp(() {
    TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        switch (methodCall.method) {
          case 'executeRequest':
            return {
              'requestId': 'test-id',
              'requestFilePath': '/test/path',
            };
          case 'getRequestStatus':
            return 0; // RequestStatus.inProgress
          case 'getResponse':
            return {
              'requestId': 'test-id',
              'statusCode': 200,
              'headers': {},
              'status': 1, // RequestStatus.completed
            };
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('executeRequest', () async {
    final result = await platform.executeRequest({
      'url': 'https://example.com',
      'method': 'GET',
    });
    expect(result['requestId'], 'test-id');
    expect(result['requestFilePath'], '/test/path');
  });

  test('getRequestStatus', () async {
    final status = await platform.getRequestStatus('test-id');
    expect(status, 0);
  });

  test('getRequestStatus returns null when request not found', () async {
    TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        if (methodCall.method == 'getRequestStatus') {
          // Симулируем PlatformException с кодом NOT_FOUND
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
    expect(response?['requestId'], 'test-id');
    expect(response?['statusCode'], 200);
  });
}
