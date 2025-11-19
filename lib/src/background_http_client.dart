import 'dart:convert';

import '../background_http_client_platform_interface.dart';
import 'models.dart';

/// Основной класс для выполнения HTTP запросов в фоновом режиме
///
/// Использует интерфейс, похожий на Dio, но выполняет запросы в фоне.
/// Каждый запрос сохраняется в файл, возвращается ID и путь к файлу.
/// Ответ от сервера также сохраняется в файл.
class BackgroundHttpClient {
  /// Платформенная реализация
  final BackgroundHttpClientPlatform _platform;

  /// Создает экземпляр [BackgroundHttpClient]
  BackgroundHttpClient({BackgroundHttpClientPlatform? platform})
      : _platform = platform ?? BackgroundHttpClientPlatform.instance;

  /// Выполняет GET запрос
  ///
  /// [url] - URL для запроса
  /// [headers] - дополнительные заголовки
  /// [queryParameters] - query параметры
  /// [timeout] - таймаут в секундах
  /// [requestId] - кастомный ID запроса (опционально). Если не указан, будет сгенерирован автоматически
  /// [retries] - количество повторных попыток при ошибках (0-10, по умолчанию 0)
  ///
  /// Возвращает [RequestInfo] с ID запроса и путем к файлу запроса
  Future<RequestInfo> get(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    int? timeout,
    String? requestId,
    int? retries,
  }) async {
    final request = HttpRequest(
      url: url,
      method: 'GET',
      headers: headers,
      queryParameters: queryParameters,
      timeout: timeout,
      requestId: requestId,
      retries: retries,
    );
    return await _executeRequest(request);
  }

  /// Выполняет POST запрос
  ///
  /// [url] - URL для запроса
  /// [data] - данные для отправки (будет преобразовано в JSON строку, если это Map или List)
  /// [headers] - дополнительные заголовки
  /// [queryParameters] - query параметры
  /// [timeout] - таймаут в секундах
  /// [requestId] - кастомный ID запроса (опционально). Если не указан, будет сгенерирован автоматически
  /// [retries] - количество повторных попыток при ошибках (0-10, по умолчанию 0)
  ///
  /// Возвращает [RequestInfo] с ID запроса и путем к файлу запроса
  Future<RequestInfo> post(
    String url, {
    dynamic data,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    int? timeout,
    String? requestId,
    int? retries,
  }) async {
    String? body;
    if (data != null) {
      if (data is String) {
        body = data;
      } else if (data is Map || data is List) {
        body = jsonEncode(data);
        // Устанавливаем Content-Type, если не указан
        headers ??= {};
        headers.putIfAbsent('Content-Type', () => 'application/json');
      } else {
        body = data.toString();
      }
    }

    final request = HttpRequest(
      url: url,
      method: 'POST',
      headers: headers,
      body: body,
      queryParameters: queryParameters,
      timeout: timeout,
      requestId: requestId,
      retries: retries,
    );
    return await _executeRequest(request);
  }

  /// Выполняет PUT запрос
  ///
  /// [url] - URL для запроса
  /// [data] - данные для отправки (будет преобразовано в JSON строку, если это Map или List)
  /// [headers] - дополнительные заголовки
  /// [queryParameters] - query параметры
  /// [timeout] - таймаут в секундах
  /// [requestId] - кастомный ID запроса (опционально). Если не указан, будет сгенерирован автоматически
  /// [retries] - количество повторных попыток при ошибках (0-10, по умолчанию 0)
  ///
  /// Возвращает [RequestInfo] с ID запроса и путем к файлу запроса
  Future<RequestInfo> put(
    String url, {
    dynamic data,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    int? timeout,
    String? requestId,
    int? retries,
  }) async {
    String? body;
    if (data != null) {
      if (data is String) {
        body = data;
      } else if (data is Map || data is List) {
        body = jsonEncode(data);
        headers ??= {};
        headers.putIfAbsent('Content-Type', () => 'application/json');
      } else {
        body = data.toString();
      }
    }

    final request = HttpRequest(
      url: url,
      method: 'PUT',
      headers: headers,
      body: body,
      queryParameters: queryParameters,
      timeout: timeout,
      requestId: requestId,
      retries: retries,
    );
    return await _executeRequest(request);
  }

  /// Выполняет DELETE запрос
  ///
  /// [url] - URL для запроса
  /// [headers] - дополнительные заголовки
  /// [queryParameters] - query параметры
  /// [timeout] - таймаут в секундах
  /// [requestId] - кастомный ID запроса (опционально). Если не указан, будет сгенерирован автоматически
  /// [retries] - количество повторных попыток при ошибках (0-10, по умолчанию 0)
  ///
  /// Возвращает [RequestInfo] с ID запроса и путем к файлу запроса
  Future<RequestInfo> delete(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    int? timeout,
    String? requestId,
    int? retries,
  }) async {
    final request = HttpRequest(
      url: url,
      method: 'DELETE',
      headers: headers,
      queryParameters: queryParameters,
      timeout: timeout,
      requestId: requestId,
      retries: retries,
    );
    return await _executeRequest(request);
  }

  /// Выполняет PATCH запрос
  ///
  /// [url] - URL для запроса
  /// [data] - данные для отправки (будет преобразовано в JSON строку, если это Map или List)
  /// [headers] - дополнительные заголовки
  /// [queryParameters] - query параметры
  /// [timeout] - таймаут в секундах
  /// [requestId] - кастомный ID запроса (опционально). Если не указан, будет сгенерирован автоматически
  /// [retries] - количество повторных попыток при ошибках (0-10, по умолчанию 0)
  ///
  /// Возвращает [RequestInfo] с ID запроса и путем к файлу запроса
  Future<RequestInfo> patch(
    String url, {
    dynamic data,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    int? timeout,
    String? requestId,
    int? retries,
  }) async {
    String? body;
    if (data != null) {
      if (data is String) {
        body = data;
      } else if (data is Map || data is List) {
        body = jsonEncode(data);
        headers ??= {};
        headers.putIfAbsent('Content-Type', () => 'application/json');
      } else {
        body = data.toString();
      }
    }

    final request = HttpRequest(
      url: url,
      method: 'PATCH',
      headers: headers,
      body: body,
      queryParameters: queryParameters,
      timeout: timeout,
      requestId: requestId,
      retries: retries,
    );
    return await _executeRequest(request);
  }

  /// Выполняет HEAD запрос
  ///
  /// [url] - URL для запроса
  /// [headers] - дополнительные заголовки
  /// [queryParameters] - query параметры
  /// [timeout] - таймаут в секундах
  /// [requestId] - кастомный ID запроса (опционально). Если не указан, будет сгенерирован автоматически
  /// [retries] - количество повторных попыток при ошибках (0-10, по умолчанию 0)
  ///
  /// Возвращает [RequestInfo] с ID запроса и путем к файлу запроса
  Future<RequestInfo> head(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    int? timeout,
    String? requestId,
    int? retries,
  }) async {
    final request = HttpRequest(
      url: url,
      method: 'HEAD',
      headers: headers,
      queryParameters: queryParameters,
      timeout: timeout,
      requestId: requestId,
      retries: retries,
    );
    return await _executeRequest(request);
  }

  /// Выполняет multipart/form-data запрос
  ///
  /// [url] - URL для запроса
  /// [fields] - текстовые поля формы
  /// [files] - файлы для загрузки (ключ - имя поля, значение - MultipartFile)
  /// [headers] - дополнительные заголовки
  /// [queryParameters] - query параметры
  /// [timeout] - таймаут в секундах
  /// [requestId] - кастомный ID запроса (опционально). Если не указан, будет сгенерирован автоматически
  /// [retries] - количество повторных попыток при ошибках (0-10, по умолчанию 0)
  ///
  /// Возвращает [RequestInfo] с ID запроса и путем к файлу запроса
  Future<RequestInfo> postMultipart(
    String url, {
    Map<String, String>? fields,
    Map<String, MultipartFile>? files,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    int? timeout,
    String? requestId,
    int? retries,
  }) async {
    final request = HttpRequest(
      url: url,
      method: 'POST',
      headers: headers,
      multipartFields: fields,
      multipartFiles: files,
      queryParameters: queryParameters,
      timeout: timeout,
      requestId: requestId,
      retries: retries,
    );
    return await _executeRequest(request);
  }

  /// Выполняет произвольный HTTP запрос
  ///
  /// [request] - объект [HttpRequest] с параметрами запроса
  ///
  /// Возвращает [RequestInfo] с ID запроса и путем к файлу запроса
  Future<RequestInfo> request(HttpRequest request) async {
    return await _executeRequest(request);
  }

  /// Внутренний метод для выполнения запроса
  Future<RequestInfo> _executeRequest(HttpRequest request) async {
    final result = await _platform.executeRequest(request.toJson());
    return RequestInfo.fromJson(result);
  }

  /// Получает статус запроса по ID
  ///
  /// [requestId] - ID запроса
  ///
  /// Возвращает текущий статус запроса или null, если запрос не найден
  Future<RequestStatus?> getRequestStatus(String requestId) async {
    final statusIndex = await _platform.getRequestStatus(requestId);
    if (statusIndex == null) {
      return null;
    }
    return RequestStatus.values[statusIndex];
  }

  /// Получает ответ от сервера по ID запроса
  ///
  /// [requestId] - ID запроса
  ///
  /// Возвращает [HttpResponse] с данными ответа или null, если ответ еще не получен
  Future<HttpResponse?> getResponse(String requestId) async {
    final result = await _platform.getResponse(requestId);
    if (result == null) {
      return null;
    }
    return HttpResponse.fromJson(result);
  }

  /// Отменяет запрос по ID
  ///
  /// [requestId] - ID запроса для отмены
  Future<void> cancelRequest(String requestId) async {
    await _platform.cancelRequest(requestId);
  }

  /// Удаляет запрос и все связанные файлы по ID
  ///
  /// [requestId] - ID запроса для удаления
  ///
  /// Удаляет:
  /// - Все WorkManager задачи (Android) или активные задачи (iOS)
  /// - Файл запроса
  /// - Файл ответа (JSON и данные)
  /// - Файл статуса
  /// - Файл body запроса (если существует)
  Future<void> deleteRequest(String requestId) async {
    await _platform.deleteRequest(requestId);
  }
}

