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

  test('getResponse', () async {
    final response = await platform.getResponse('test-id');
    expect(response, isNotNull);
    expect(response?['requestId'], 'test-id');
    expect(response?['statusCode'], 200);
  });
}
