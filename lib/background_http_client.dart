/// Плагин для выполнения HTTP запросов в фоновом режиме
///
/// Этот плагин позволяет выполнять стандартные HTTP запросы (GET, POST, PUT, DELETE, PATCH, HEAD)
/// в фоновом режиме. Запросы сохраняются в файлы, и по ID можно получить статус и ответ.
library;

export 'src/background_http_client.dart';
export 'src/models.dart';
