/// Статусы выполнения HTTP запроса
enum RequestStatus {
  /// Запрос в процессе выполнения
  inProgress,

  /// Получен ответ от сервера
  completed,

  /// Запрос завершился с ошибкой
  failed,
}

/// Модель для multipart файла
class MultipartFile {
  /// Путь к файлу
  final String filePath;

  /// Имя файла (опционально)
  final String? filename;

  /// MIME тип файла (опционально)
  final String? contentType;

  MultipartFile({
    required this.filePath,
    this.filename,
    this.contentType,
  });

  Map<String, dynamic> toJson() {
    return {
      'filePath': filePath,
      if (filename != null) 'filename': filename,
      if (contentType != null) 'contentType': contentType,
    };
  }

  factory MultipartFile.fromJson(Map<String, dynamic> json) {
    return MultipartFile(
      filePath: json['filePath'] as String,
      filename: json['filename'] as String?,
      contentType: json['contentType'] as String?,
    );
  }
}

/// Модель HTTP запроса
class HttpRequest {
  /// URL для запроса
  final String url;

  /// HTTP метод (GET, POST, PUT, DELETE, PATCH, HEAD)
  final String method;

  /// Заголовки запроса
  final Map<String, String>? headers;

  /// Тело запроса (для POST, PUT, PATCH)
  final String? body;

  /// Query параметры
  final Map<String, dynamic>? queryParameters;

  /// Таймаут запроса в секундах
  final int? timeout;

  /// Multipart поля (для multipart/form-data)
  final Map<String, String>? multipartFields;

  /// Multipart файлы (для multipart/form-data)
  final Map<String, MultipartFile>? multipartFiles;

  /// Кастомный ID запроса (опционально). Если не указан, будет сгенерирован автоматически
  final String? requestId;

  /// Количество повторных попыток при ошибках (0-10, по умолчанию 0)
  /// Используется экспоненциальная задержка между попытками
  final int? retries;

  /// Запас времени в секундах для определения зависших запросов в процессе выполнения
  /// По умолчанию 60 секунд. Запрос считается зависшим, если прошло больше (timeout + stuckTimeoutBuffer)
  final int? stuckTimeoutBuffer;

  /// Максимальное время ожидания в очереди в секундах
  /// По умолчанию 600 секунд (10 минут). Запрос считается зависшим в очереди, если прошло больше этого времени
  final int? queueTimeout;

  HttpRequest({
    required this.url,
    required this.method,
    this.headers,
    this.body,
    this.queryParameters,
    this.timeout,
    this.multipartFields,
    this.multipartFiles,
    this.requestId,
    this.retries,
    this.stuckTimeoutBuffer,
    this.queueTimeout,
  });

  /// Создает объект из JSON
  factory HttpRequest.fromJson(Map<String, dynamic> json) {
    Map<String, MultipartFile>? multipartFiles;
    if (json['multipartFiles'] != null) {
      multipartFiles = {};
      final filesMap = json['multipartFiles'] as Map<dynamic, dynamic>;
      filesMap.forEach((key, value) {
        multipartFiles![key as String] = MultipartFile.fromJson(value as Map<String, dynamic>);
      });
    }

    return HttpRequest(
      url: json['url'] as String,
      method: json['method'] as String,
      headers: json['headers'] != null ? Map<String, String>.from(json['headers'] as Map<dynamic, dynamic>) : null,
      body: json['body'] as String?,
      queryParameters: json['queryParameters'] != null
          ? Map<String, dynamic>.from(json['queryParameters'] as Map<dynamic, dynamic>)
          : null,
      timeout: json['timeout'] as int?,
      multipartFields: json['multipartFields'] != null
          ? Map<String, String>.from(json['multipartFields'] as Map<dynamic, dynamic>)
          : null,
      multipartFiles: multipartFiles,
      requestId: json['requestId'] as String?,
      retries: json['retries'] as int?,
      stuckTimeoutBuffer: json['stuckTimeoutBuffer'] as int?,
      queueTimeout: json['queueTimeout'] as int?,
    );
  }

  /// Преобразует объект в JSON
  Map<String, dynamic> toJson() {
    Map<String, dynamic>? multipartFilesJson;
    if (multipartFiles != null) {
      multipartFilesJson = {};
      multipartFiles!.forEach((key, value) {
        multipartFilesJson![key] = value.toJson();
      });
    }

    return {
      'url': url,
      'method': method,
      if (headers != null) 'headers': headers,
      if (body != null) 'body': body,
      if (queryParameters != null) 'queryParameters': queryParameters,
      if (timeout != null) 'timeout': timeout,
      if (multipartFields != null) 'multipartFields': multipartFields,
      if (multipartFilesJson != null) 'multipartFiles': multipartFilesJson,
      if (requestId != null) 'requestId': requestId,
      if (retries != null) 'retries': retries,
      if (stuckTimeoutBuffer != null) 'stuckTimeoutBuffer': stuckTimeoutBuffer,
      if (queueTimeout != null) 'queueTimeout': queueTimeout,
    };
  }
}

/// Модель HTTP ответа
class HttpResponse {
  /// ID запроса
  final String requestId;

  /// Статус код ответа
  final int statusCode;

  /// Заголовки ответа
  final Map<String, String> headers;

  /// Тело ответа (если небольшое)
  final String? body;

  /// Путь к файлу с ответом
  final String? responseFilePath;

  /// Статус запроса
  final RequestStatus status;

  /// Сообщение об ошибке (если есть)
  final String? error;

  HttpResponse({
    required this.requestId,
    required this.statusCode,
    required this.headers,
    this.body,
    this.responseFilePath,
    required this.status,
    this.error,
  });

  /// Создает объект из JSON
  factory HttpResponse.fromJson(Map<String, dynamic> json) {
    return HttpResponse(
      requestId: json['requestId'] as String,
      statusCode: json['statusCode'] as int,
      headers: json['headers'] != null
          ? Map<String, String>.from(json['headers'] as Map<dynamic, dynamic>)
          : <String, String>{},
      body: json['body'] as String?,
      responseFilePath: json['responseFilePath'] as String?,
      status: RequestStatus.values[json['status'] as int],
      error: json['error'] as String?,
    );
  }

  /// Преобразует объект в JSON
  Map<String, dynamic> toJson() {
    return {
      'requestId': requestId,
      'statusCode': statusCode,
      'headers': headers,
      if (body != null) 'body': body,
      if (responseFilePath != null) 'responseFilePath': responseFilePath,
      'status': status.index,
      if (error != null) 'error': error,
    };
  }
}

/// Информация о запросе (ID и путь к файлу запроса)
class RequestInfo {
  /// Уникальный ID запроса
  final String requestId;

  /// Путь к файлу с данными запроса
  final String requestFilePath;

  RequestInfo({
    required this.requestId,
    required this.requestFilePath,
  });

  /// Создает объект из JSON
  factory RequestInfo.fromJson(Map<String, dynamic> json) {
    return RequestInfo(
      requestId: json['requestId'] as String,
      requestFilePath: json['requestFilePath'] as String,
    );
  }

  /// Преобразует объект в JSON
  Map<String, dynamic> toJson() {
    return {
      'requestId': requestId,
      'requestFilePath': requestFilePath,
    };
  }
}

/// Информация о задаче в нативном HTTP сервисе
class TaskInfo {
  /// Уникальный ID задачи
  final String id;

  /// Статус задачи (индекс в enum RequestStatus)
  final int status;

  /// Путь к файлу с данными задачи
  final String path;

  /// Дата регистрации задачи в нативном HTTP сервисе (timestamp в миллисекундах)
  final int registrationDate;

  /// JSON ответа (только для getResponse, опционально)
  final Map<String, dynamic>? responseJson;

  TaskInfo({
    required this.id,
    required this.status,
    required this.path,
    required this.registrationDate,
    this.responseJson,
  });

  /// Создает объект из JSON
  factory TaskInfo.fromJson(Map<String, dynamic> json) {
    return TaskInfo(
      id: json['id'] as String,
      status: json['status'] as int,
      path: json['path'] as String,
      registrationDate: json['registrationDate'] as int,
      responseJson: json['responseJson'] != null
          ? Map<String, dynamic>.from(json['responseJson'] as Map<dynamic, dynamic>)
          : null,
    );
  }

  /// Преобразует объект в JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'status': status,
      'path': path,
      'registrationDate': registrationDate,
      if (responseJson != null) 'responseJson': responseJson,
    };
  }

  /// Получает статус как enum
  RequestStatus get statusEnum => RequestStatus.values[status];

  /// Получает дату регистрации как DateTime
  DateTime get registrationDateTime => DateTime.fromMillisecondsSinceEpoch(registrationDate);
}

/// Информация о задаче в ожидании
class PendingTask {
  /// Уникальный ID задачи
  final String requestId;

  /// Дата регистрации задачи (timestamp в миллисекундах)
  final int registrationDate;

  PendingTask({
    required this.requestId,
    required this.registrationDate,
  });

  /// Создает объект из JSON
  factory PendingTask.fromJson(Map<String, dynamic> json) {
    return PendingTask(
      requestId: json['requestId'] as String,
      registrationDate: json['registrationDate'] as int,
    );
  }

  /// Преобразует объект в JSON
  Map<String, dynamic> toJson() {
    return {
      'requestId': requestId,
      'registrationDate': registrationDate,
    };
  }

  /// Получает дату регистрации как DateTime
  DateTime get registrationDateTime => DateTime.fromMillisecondsSinceEpoch(registrationDate);
}
