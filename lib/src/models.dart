/// HTTP request execution statuses
enum RequestStatus {
  /// Request is in progress
  inProgress,

  /// Response received from the server
  completed,

  /// Request finished with an error
  failed,
}

/// Model for a multipart file
class MultipartFile {
  /// File path
  final String filePath;

  /// File name (optional)
  final String? filename;

  /// MIME type (optional)
  final String? contentType;

  /// Creates a [MultipartFile] instance
  ///
  /// [filePath] - path to the file
  /// [filename] - optional file name
  /// [contentType] - optional MIME type
  MultipartFile({
    required this.filePath,
    this.filename,
    this.contentType,
  });

  /// Converts the object to JSON
  Map<String, dynamic> toJson() {
    return {
      'filePath': filePath,
      if (filename != null) 'filename': filename,
      if (contentType != null) 'contentType': contentType,
    };
  }

  /// Creates a [MultipartFile] from JSON
  factory MultipartFile.fromJson(Map<String, dynamic> json) {
    return MultipartFile(
      filePath: json['filePath'] as String,
      filename: json['filename'] as String?,
      contentType: json['contentType'] as String?,
    );
  }
}

/// HTTP request model
class HttpRequest {
  /// URL for the request
  final String url;

  /// HTTP method (GET, POST, PUT, DELETE, PATCH, HEAD)
  final String method;

  /// Request headers
  final Map<String, String>? headers;

  /// Request body (for POST, PUT, PATCH)
  final String? body;

  /// Query parameters
  final Map<String, dynamic>? queryParameters;

  /// Request timeout in seconds
  final int? timeout;

  /// Multipart fields (for multipart/form-data)
  final Map<String, String>? multipartFields;

  /// Multipart files (for multipart/form-data)
  final Map<String, MultipartFile>? multipartFiles;

  /// Custom request ID (optional). If not provided, it will be generated automatically
  final String? requestId;

  /// Number of retry attempts on errors (0-10, default 0)
  /// Uses exponential backoff between attempts
  final int? retries;

  /// Buffer time in seconds to detect stuck requests during execution
  /// Default is 60 seconds. A request is considered stuck if more than (timeout + stuckTimeoutBuffer) has passed.
  final int? stuckTimeoutBuffer;

  /// Maximum waiting time in the queue in seconds
  /// Default is 600 seconds (10 minutes). A request is considered stuck in the queue if more than this time has passed.
  final int? queueTimeout;

  /// Creates an [HttpRequest] instance
  ///
  /// [url] - URL for the request
  /// [method] - HTTP method (GET, POST, PUT, DELETE, PATCH, HEAD)
  /// [headers] - optional request headers
  /// [body] - optional request body (for POST, PUT, PATCH)
  /// [queryParameters] - optional query parameters
  /// [timeout] - optional request timeout in seconds
  /// [multipartFields] - optional multipart fields (for multipart/form-data)
  /// [multipartFiles] - optional multipart files (for multipart/form-data)
  /// [requestId] - optional custom request ID (if not provided, will be generated automatically)
  /// [retries] - number of retry attempts on errors (0-10, default 0)
  /// [stuckTimeoutBuffer] - buffer time in seconds to detect stuck requests (default 60)
  /// [queueTimeout] - maximum waiting time in the queue in seconds (default 600)
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

  /// Creates an object from JSON
  factory HttpRequest.fromJson(Map<String, dynamic> json) {
    Map<String, MultipartFile>? multipartFiles;
    if (json['multipartFiles'] != null) {
      multipartFiles = {};
      final filesMap = json['multipartFiles'] as Map<dynamic, dynamic>;
      filesMap.forEach((key, value) {
        multipartFiles![key as String] =
            MultipartFile.fromJson(value as Map<String, dynamic>);
      });
    }

    return HttpRequest(
      url: json['url'] as String,
      method: json['method'] as String,
      headers: json['headers'] != null
          ? Map<String, String>.from(json['headers'] as Map<dynamic, dynamic>)
          : null,
      body: json['body'] as String?,
      queryParameters: json['queryParameters'] != null
          ? Map<String, dynamic>.from(
              json['queryParameters'] as Map<dynamic, dynamic>)
          : null,
      timeout: json['timeout'] as int?,
      multipartFields: json['multipartFields'] != null
          ? Map<String, String>.from(
              json['multipartFields'] as Map<dynamic, dynamic>)
          : null,
      multipartFiles: multipartFiles,
      requestId: json['requestId'] as String?,
      retries: json['retries'] as int?,
      stuckTimeoutBuffer: json['stuckTimeoutBuffer'] as int?,
      queueTimeout: json['queueTimeout'] as int?,
    );
  }

  /// Converts the object to JSON
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

/// HTTP response model
class HttpResponse {
  /// Request ID
  final String requestId;

  /// Response status code
  final int statusCode;

  /// Response headers
  final Map<String, String> headers;

  /// Response body (if small)
  final String? body;

  /// Path to the response file
  final String? responseFilePath;

  /// Request status
  final RequestStatus status;

  /// Error message (if any)
  final String? error;

  /// Creates an [HttpResponse] instance
  ///
  /// [requestId] - request ID
  /// [statusCode] - HTTP status code
  /// [headers] - response headers
  /// [body] - optional response body (if small)
  /// [responseFilePath] - optional path to the response file
  /// [status] - request status
  /// [error] - optional error message
  HttpResponse({
    required this.requestId,
    required this.statusCode,
    required this.headers,
    this.body,
    this.responseFilePath,
    required this.status,
    this.error,
  });

  /// Creates an object from JSON
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

  /// Converts the object to JSON
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

/// Information about a request (ID and path to the request file)
class RequestInfo {
  /// Unique request ID
  final String requestId;

  /// Path to the file with request data
  final String requestFilePath;

  RequestInfo({
    required this.requestId,
    required this.requestFilePath,
  });

  /// Creates an object from JSON
  factory RequestInfo.fromJson(Map<String, dynamic> json) {
    return RequestInfo(
      requestId: json['requestId'] as String,
      requestFilePath: json['requestFilePath'] as String,
    );
  }

  /// Converts the object to JSON
  Map<String, dynamic> toJson() {
    return {
      'requestId': requestId,
      'requestFilePath': requestFilePath,
    };
  }
}

/// Information about a task in the native HTTP service
class TaskInfo {
  /// Unique task ID
  final String id;

  /// Task status (index in the RequestStatus enum)
  final int status;

  /// Path to the file with task data
  final String path;

  /// Task registration date in the native HTTP service (timestamp in milliseconds)
  final int registrationDate;

  /// Response JSON (only for getResponse, optional)
  final Map<String, dynamic>? responseJson;

  TaskInfo({
    required this.id,
    required this.status,
    required this.path,
    required this.registrationDate,
    this.responseJson,
  });

  /// Creates an object from JSON
  factory TaskInfo.fromJson(Map<String, dynamic> json) {
    return TaskInfo(
      id: json['id'] as String,
      status: json['status'] as int,
      path: json['path'] as String,
      registrationDate: json['registrationDate'] as int,
      responseJson: json['responseJson'] != null
          ? Map<String, dynamic>.from(
              json['responseJson'] as Map<dynamic, dynamic>)
          : null,
    );
  }

  /// Converts the object to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'status': status,
      'path': path,
      'registrationDate': registrationDate,
      if (responseJson != null) 'responseJson': responseJson,
    };
  }

  /// Gets status as enum
  RequestStatus get statusEnum => RequestStatus.values[status];

  /// Gets registration date as DateTime
  DateTime get registrationDateTime =>
      DateTime.fromMillisecondsSinceEpoch(registrationDate);
}

/// Information about a pending task
class PendingTask {
  /// Unique task ID
  final String requestId;

  /// Task registration date (timestamp in milliseconds)
  final int registrationDate;

  PendingTask({
    required this.requestId,
    required this.registrationDate,
  });

  /// Creates an object from JSON
  factory PendingTask.fromJson(Map<String, dynamic> json) {
    return PendingTask(
      requestId: json['requestId'] as String,
      registrationDate: json['registrationDate'] as int,
    );
  }

  /// Converts the object to JSON
  Map<String, dynamic> toJson() {
    return {
      'requestId': requestId,
      'registrationDate': registrationDate,
    };
  }

  /// Gets registration date as DateTime
  DateTime get registrationDateTime =>
      DateTime.fromMillisecondsSinceEpoch(registrationDate);
}

/// Task queue statistics
class QueueStats {
  /// Number of tasks in the queue (waiting to be executed)
  final int pendingCount;

  /// Number of active tasks (currently executing)
  final int activeCount;

  /// Maximum number of concurrent tasks
  final int maxConcurrent;

  /// Maximum queue size
  final int maxQueueSize;

  QueueStats({
    required this.pendingCount,
    required this.activeCount,
    required this.maxConcurrent,
    required this.maxQueueSize,
  });

  /// Creates an object from JSON
  factory QueueStats.fromJson(Map<String, dynamic> json) {
    return QueueStats(
      pendingCount: json['pendingCount'] as int? ?? 0,
      activeCount: json['activeCount'] as int? ?? 0,
      maxConcurrent: json['maxConcurrent'] as int? ?? 30,
      maxQueueSize: json['maxQueueSize'] as int? ?? 10000,
    );
  }

  /// Converts the object to JSON
  Map<String, dynamic> toJson() {
    return {
      'pendingCount': pendingCount,
      'activeCount': activeCount,
      'maxConcurrent': maxConcurrent,
      'maxQueueSize': maxQueueSize,
    };
  }

  /// Total number of tasks (in the queue + active)
  int get totalCount => pendingCount + activeCount;

  /// Number of available slots for new tasks
  int get availableSlots => maxConcurrent - activeCount;

  /// Whether the queue is full
  bool get isQueueFull => pendingCount >= maxQueueSize;

  @override
  String toString() {
    return 'QueueStats(pending: $pendingCount, active: $activeCount, maxConcurrent: $maxConcurrent, maxQueueSize: $maxQueueSize)';
  }
}
