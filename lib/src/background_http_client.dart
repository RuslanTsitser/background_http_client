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
  /// [stuckTimeoutBuffer] - запас времени в секундах для определения зависших запросов в процессе выполнения (по умолчанию 60)
  /// [queueTimeout] - максимальное время ожидания в очереди в секундах (по умолчанию 600 = 10 минут)
  ///
  /// Возвращает [TaskInfo] с информацией о созданной задаче
  Future<TaskInfo> get(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    int? timeout,
    String? requestId,
    int? retries,
    int? stuckTimeoutBuffer,
    int? queueTimeout,
  }) async {
    final request = HttpRequest(
      url: url,
      method: 'GET',
      headers: headers,
      queryParameters: queryParameters,
      timeout: timeout,
      requestId: requestId,
      retries: retries,
      stuckTimeoutBuffer: stuckTimeoutBuffer,
      queueTimeout: queueTimeout,
    );
    return await _createRequest(request);
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
  /// [stuckTimeoutBuffer] - запас времени в секундах для определения зависших запросов в процессе выполнения (по умолчанию 60)
  /// [queueTimeout] - максимальное время ожидания в очереди в секундах (по умолчанию 600 = 10 минут)
  ///
  /// Возвращает [TaskInfo] с информацией о созданной задаче
  Future<TaskInfo> post(
    String url, {
    dynamic data,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    int? timeout,
    String? requestId,
    int? retries,
    int? stuckTimeoutBuffer,
    int? queueTimeout,
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
      stuckTimeoutBuffer: stuckTimeoutBuffer,
      queueTimeout: queueTimeout,
    );
    return await _createRequest(request);
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
  /// [stuckTimeoutBuffer] - запас времени в секундах для определения зависших запросов в процессе выполнения (по умолчанию 60)
  /// [queueTimeout] - максимальное время ожидания в очереди в секундах (по умолчанию 600 = 10 минут)
  ///
  /// Возвращает [TaskInfo] с информацией о созданной задаче
  Future<TaskInfo> put(
    String url, {
    dynamic data,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    int? timeout,
    String? requestId,
    int? retries,
    int? stuckTimeoutBuffer,
    int? queueTimeout,
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
      stuckTimeoutBuffer: stuckTimeoutBuffer,
      queueTimeout: queueTimeout,
    );
    return await _createRequest(request);
  }

  /// Выполняет DELETE запрос
  ///
  /// [url] - URL для запроса
  /// [headers] - дополнительные заголовки
  /// [queryParameters] - query параметры
  /// [timeout] - таймаут в секундах
  /// [requestId] - кастомный ID запроса (опционально). Если не указан, будет сгенерирован автоматически
  /// [retries] - количество повторных попыток при ошибках (0-10, по умолчанию 0)
  /// [stuckTimeoutBuffer] - запас времени в секундах для определения зависших запросов в процессе выполнения (по умолчанию 60)
  /// [queueTimeout] - максимальное время ожидания в очереди в секундах (по умолчанию 600 = 10 минут)
  ///
  /// Возвращает [TaskInfo] с информацией о созданной задаче
  Future<TaskInfo> delete(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    int? timeout,
    String? requestId,
    int? retries,
    int? stuckTimeoutBuffer,
    int? queueTimeout,
  }) async {
    final request = HttpRequest(
      url: url,
      method: 'DELETE',
      headers: headers,
      queryParameters: queryParameters,
      timeout: timeout,
      requestId: requestId,
      retries: retries,
      stuckTimeoutBuffer: stuckTimeoutBuffer,
      queueTimeout: queueTimeout,
    );
    return await _createRequest(request);
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
  /// [stuckTimeoutBuffer] - запас времени в секундах для определения зависших запросов в процессе выполнения (по умолчанию 60)
  /// [queueTimeout] - максимальное время ожидания в очереди в секундах (по умолчанию 600 = 10 минут)
  ///
  /// Возвращает [TaskInfo] с информацией о созданной задаче
  Future<TaskInfo> patch(
    String url, {
    dynamic data,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    int? timeout,
    String? requestId,
    int? retries,
    int? stuckTimeoutBuffer,
    int? queueTimeout,
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
      stuckTimeoutBuffer: stuckTimeoutBuffer,
      queueTimeout: queueTimeout,
    );
    return await _createRequest(request);
  }

  /// Выполняет HEAD запрос
  ///
  /// [url] - URL для запроса
  /// [headers] - дополнительные заголовки
  /// [queryParameters] - query параметры
  /// [timeout] - таймаут в секундах
  /// [requestId] - кастомный ID запроса (опционально). Если не указан, будет сгенерирован автоматически
  /// [retries] - количество повторных попыток при ошибках (0-10, по умолчанию 0)
  /// [stuckTimeoutBuffer] - запас времени в секундах для определения зависших запросов в процессе выполнения (по умолчанию 60)
  /// [queueTimeout] - максимальное время ожидания в очереди в секундах (по умолчанию 600 = 10 минут)
  ///
  /// Возвращает [TaskInfo] с информацией о созданной задаче
  Future<TaskInfo> head(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    int? timeout,
    String? requestId,
    int? retries,
    int? stuckTimeoutBuffer,
    int? queueTimeout,
  }) async {
    final request = HttpRequest(
      url: url,
      method: 'HEAD',
      headers: headers,
      queryParameters: queryParameters,
      timeout: timeout,
      requestId: requestId,
      retries: retries,
      stuckTimeoutBuffer: stuckTimeoutBuffer,
      queueTimeout: queueTimeout,
    );
    return await _createRequest(request);
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
  /// [stuckTimeoutBuffer] - запас времени в секундах для определения зависших запросов в процессе выполнения (по умолчанию 60)
  /// [queueTimeout] - максимальное время ожидания в очереди в секундах (по умолчанию 600 = 10 минут)
  ///
  /// Возвращает [TaskInfo] с информацией о созданной задаче
  Future<TaskInfo> postMultipart(
    String url, {
    Map<String, String>? fields,
    Map<String, MultipartFile>? files,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    int? timeout,
    String? requestId,
    int? retries,
    int? stuckTimeoutBuffer,
    int? queueTimeout,
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
      stuckTimeoutBuffer: stuckTimeoutBuffer,
      queueTimeout: queueTimeout,
    );
    return await _createRequest(request);
  }

  /// Выполняет произвольный HTTP запрос
  ///
  /// [request] - объект [HttpRequest] с параметрами запроса
  ///
  /// Возвращает [TaskInfo] с информацией о созданной задаче
  Future<TaskInfo> request(HttpRequest request) async {
    return await _createRequest(request);
  }

  /// Внутренний метод для создания запроса
  Future<TaskInfo> _createRequest(HttpRequest request) async {
    final result = await _platform.createRequest(request.toJson());
    return TaskInfo.fromJson(result);
  }

  /// Получает статус задачи по ID
  ///
  /// [requestId] - ID задачи
  ///
  /// Возвращает [TaskInfo] с информацией о задаче или null, если задача не найдена
  Future<TaskInfo?> getRequestStatus(String requestId) async {
    final result = await _platform.getRequestStatus(requestId);
    if (result == null) {
      return null;
    }
    return TaskInfo.fromJson(result);
  }

  /// Получает ответ от сервера по ID задачи
  ///
  /// [requestId] - ID задачи
  ///
  /// Возвращает [TaskInfo] с данными ответа (включая responseJson) или null, если задача не найдена
  Future<TaskInfo?> getResponse(String requestId) async {
    final result = await _platform.getResponse(requestId);
    if (result == null) {
      return null;
    }
    return TaskInfo.fromJson(result);
  }

  /// Отменяет задачу по ID
  ///
  /// [requestId] - ID задачи для отмены
  ///
  /// Возвращает true если задача отменена, false если не получилось отменить, null если задачи не существует
  Future<bool?> cancelRequest(String requestId) async {
    return await _platform.cancelRequest(requestId);
  }

  /// Удаляет задачу и все связанные файлы по ID
  ///
  /// [requestId] - ID задачи для удаления
  ///
  /// Возвращает true если задача удалена, false если не получилось удалить, null если задачи не существует
  ///
  /// Удаляет:
  /// - Все WorkManager задачи (Android) или активные задачи (iOS)
  /// - Файл запроса
  /// - Файл ответа (JSON и данные)
  /// - Файл статуса
  /// - Файл body запроса (если существует)
  Future<bool?> deleteRequest(String requestId) async {
    return await _platform.deleteRequest(requestId);
  }

  /// Получает stream с ID завершенных задач
  ///
  /// Возвращает Stream<String> с ID задач, которые были успешно завершены
  /// Каждый раз, когда задача успешно завершается (HTTP статус 200-299), в stream отправляется её ID
  Stream<String> getCompletedTasksStream() {
    return _platform.getCompletedTasksStream();
  }

  /// Получает список задач в ожидании с датами добавления
  ///
  /// Возвращает список [PendingTask] с ID задач и датами их регистрации
  Future<List<PendingTask>> getPendingTasks() async {
    final result = await _platform.getPendingTasks();
    return result.map((json) => PendingTask.fromJson(json)).toList();
  }

  /// Отменяет все задачи
  ///
  /// Возвращает количество отмененных задач
  Future<int> cancelAllTasks() async {
    return await _platform.cancelAllTasks();
  }

  // ============== Методы управления очередью ==============

  /// Получает статистику очереди задач
  ///
  /// Возвращает [QueueStats] с информацией о состоянии очереди:
  /// - pendingCount: количество задач в очереди (ожидающих выполнения)
  /// - activeCount: количество активных задач (выполняющихся прямо сейчас)
  /// - maxConcurrent: максимальное количество одновременных задач
  /// - maxQueueSize: максимальный размер очереди
  Future<QueueStats> getQueueStats() async {
    final result = await _platform.getQueueStats();
    return QueueStats.fromJson(result);
  }

  /// Устанавливает максимальное количество одновременных задач
  ///
  /// [count] - максимальное количество одновременных задач (минимум 1, по умолчанию 30)
  ///
  /// Если увеличить лимит, плагин автоматически запустит дополнительные задачи из очереди.
  /// Если уменьшить лимит, текущие активные задачи не будут отменены,
  /// но новые не будут запускаться пока количество активных не станет меньше нового лимита.
  Future<bool> setMaxConcurrentTasks(int count) async {
    if (count < 1) {
      throw ArgumentError('count must be at least 1');
    }
    return await _platform.setMaxConcurrentTasks(count);
  }

  /// Устанавливает максимальный размер очереди
  ///
  /// [size] - максимальный размер очереди (минимум 1, по умолчанию 10000)
  ///
  /// Если очередь переполнена, новые задачи будут отклонены.
  Future<bool> setMaxQueueSize(int size) async {
    if (size < 1) {
      throw ArgumentError('size must be at least 1');
    }
    return await _platform.setMaxQueueSize(size);
  }

  /// Синхронизирует состояние очереди с реальным состоянием задач
  ///
  /// Вызывается для очистки "зависших" задач:
  /// - Задачи, которые помечены как активные, но не выполняются в WorkManager
  /// - Задачи в очереди, для которых не существует файла запроса
  ///
  /// Рекомендуется вызывать при старте приложения.
  Future<bool> syncQueueState() async {
    return await _platform.syncQueueState();
  }

  /// Принудительно обрабатывает очередь
  ///
  /// Запускает ожидающие задачи, если есть свободные слоты.
  /// Обычно это происходит автоматически, но можно вызвать вручную
  /// для немедленного запуска задач.
  Future<bool> processQueue() async {
    return await _platform.processQueue();
  }
}
