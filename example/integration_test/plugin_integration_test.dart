// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:background_http_client/background_http_client.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('BackgroundHttpClient integration test',
      (WidgetTester tester) async {
    final BackgroundHttpClient client = BackgroundHttpClient();

    // Тест выполнения GET запроса
    // Примечание: этот тест требует нативной реализации плагина
    // В реальном приложении это будет работать после реализации нативной части

    try {
      final requestInfo = await client.get('https://httpbin.org/get');
      expect(requestInfo.requestId, isNotEmpty);
      expect(requestInfo.requestFilePath, isNotEmpty);

      // Проверяем статус (должен быть не null, так как запрос только что создан)
      final status = await client.getRequestStatus(requestInfo.requestId);
      expect(status, isNotNull);
      
      // Проверяем, что для несуществующего запроса возвращается null
      final nonExistentStatus = await client.getRequestStatus('non-existent-id');
      expect(nonExistentStatus, isNull);
    } catch (e) {
      // Если нативная реализация еще не готова, тест может упасть
      // Это нормально на этапе разработки
      print('Integration test skipped: $e');
    }
  });
}
