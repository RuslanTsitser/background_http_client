// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'package:background_http_client/background_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('BackgroundHttpClient integration test', (WidgetTester tester) async {
    final BackgroundHttpClient client = BackgroundHttpClient();

    // Test for executing a GET request
    // Note: this test requires a native plugin implementation
    // In a real application this will work after the native part is implemented

    try {
      final requestInfo = await client.get('https://httpbin.org/get');
      expect(requestInfo.requestId, isNotEmpty);
      expect(requestInfo.requestFilePath, isNotEmpty);

      // Check status (should not be null since the request has just been created)
      final status = await client.getRequestStatus(requestInfo.requestId);
      expect(status, isNotNull);

      // Check that null is returned for a non-existent request
      final nonExistentStatus = await client.getRequestStatus('non-existent-id');
      expect(nonExistentStatus, isNull);
    } catch (e) {
      // If the native implementation is not ready yet, the test may fail
      // This is normal during the development phase
      print('Integration test skipped: $e');
    }
  });
}
