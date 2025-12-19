import 'dart:convert';

import '../background_http_client_platform_interface.dart';
import 'models.dart';

/// Main class for executing HTTP requests in the background.
///
/// Uses an interface similar to Dio, but executes requests in the background.
/// Each request is saved to a file; the ID and file path are returned.
/// The server response is also saved to a file.
class BackgroundHttpClient {
  /// Platform implementation
  final BackgroundHttpClientPlatform _platform;

  /// Creates an instance of [BackgroundHttpClient]
  BackgroundHttpClient({BackgroundHttpClientPlatform? platform})
      : _platform = platform ?? BackgroundHttpClientPlatform.instance;

  /// Executes a GET request
  ///
  /// [url] - URL for the request
  /// [headers] - additional headers
  /// [queryParameters] - query parameters
  /// [timeout] - timeout in seconds
  /// [requestId] - custom request ID (optional). If not provided, it will be generated automatically
  /// [retries] - number of retry attempts on errors (0-10, default 0)
  /// [stuckTimeoutBuffer] - buffer time in seconds to detect stuck requests during execution (default 60)
  /// [queueTimeout] - maximum queue waiting time in seconds (default 600 = 10 minutes)
  ///
  /// Returns [TaskInfo] with information about the created task
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

  /// Executes a POST request
  ///
  /// [url] - URL for the request
  /// [data] - data to send (will be converted to a JSON string if it is a Map or List)
  /// [headers] - additional headers
  /// [queryParameters] - query parameters
  /// [timeout] - timeout in seconds
  /// [requestId] - custom request ID (optional). If not provided, it will be generated automatically
  /// [retries] - number of retry attempts on errors (0-10, default 0)
  /// [stuckTimeoutBuffer] - buffer time in seconds to detect stuck requests during execution (default 60)
  /// [queueTimeout] - maximum queue waiting time in seconds (default 600 = 10 minutes)
  ///
  /// Returns [TaskInfo] with information about the created task
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
        // Set Content-Type if not provided
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

  /// Executes a PUT request
  ///
  /// [url] - URL for the request
  /// [data] - data to send (will be converted to a JSON string if it is a Map or List)
  /// [headers] - additional headers
  /// [queryParameters] - query parameters
  /// [timeout] - timeout in seconds
  /// [requestId] - custom request ID (optional). If not provided, it will be generated automatically
  /// [retries] - number of retry attempts on errors (0-10, default 0)
  /// [stuckTimeoutBuffer] - buffer time in seconds to detect stuck requests during execution (default 60)
  /// [queueTimeout] - maximum queue waiting time in seconds (default 600 = 10 minutes)
  ///
  /// Returns [TaskInfo] with information about the created task
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

  /// Executes a DELETE request
  ///
  /// [url] - URL for the request
  /// [headers] - additional headers
  /// [queryParameters] - query parameters
  /// [timeout] - timeout in seconds
  /// [requestId] - custom request ID (optional). If not provided, it will be generated automatically
  /// [retries] - number of retry attempts on errors (0-10, default 0)
  /// [stuckTimeoutBuffer] - buffer time in seconds to detect stuck requests during execution (default 60)
  /// [queueTimeout] - maximum queue waiting time in seconds (default 600 = 10 minutes)
  ///
  /// Returns [TaskInfo] with information about the created task
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

  /// Executes a PATCH request
  ///
  /// [url] - URL for the request
  /// [data] - data to send (will be converted to a JSON string if it is a Map or List)
  /// [headers] - additional headers
  /// [queryParameters] - query parameters
  /// [timeout] - timeout in seconds
  /// [requestId] - custom request ID (optional). If not provided, it will be generated automatically
  /// [retries] - number of retry attempts on errors (0-10, default 0)
  /// [stuckTimeoutBuffer] - buffer time in seconds to detect stuck requests during execution (default 60)
  /// [queueTimeout] - maximum queue waiting time in seconds (default 600 = 10 minutes)
  ///
  /// Returns [TaskInfo] with information about the created task
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

  /// Executes a HEAD request
  ///
  /// [url] - URL for the request
  /// [headers] - additional headers
  /// [queryParameters] - query parameters
  /// [timeout] - timeout in seconds
  /// [requestId] - custom request ID (optional). If not provided, it will be generated automatically
  /// [retries] - number of retry attempts on errors (0-10, default 0)
  /// [stuckTimeoutBuffer] - buffer time in seconds to detect stuck requests during execution (default 60)
  /// [queueTimeout] - maximum queue waiting time in seconds (default 600 = 10 minutes)
  ///
  /// Returns [TaskInfo] with information about the created task
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

  /// Executes a multipart/form-data request
  ///
  /// [url] - URL for the request
  /// [fields] - text form fields
  /// [files] - files to upload (key - field name, value - MultipartFile)
  /// [headers] - additional headers
  /// [queryParameters] - query parameters
  /// [timeout] - timeout in seconds
  /// [requestId] - custom request ID (optional). If not provided, it will be generated automatically
  /// [retries] - number of retry attempts on errors (0-10, default 0)
  /// [stuckTimeoutBuffer] - buffer time in seconds to detect stuck requests during execution (default 60)
  /// [queueTimeout] - maximum queue waiting time in seconds (default 600 = 10 minutes)
  ///
  /// Returns [TaskInfo] with information about the created task
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

  /// Executes an arbitrary HTTP request
  ///
  /// [request] - [HttpRequest] object with request parameters
  ///
  /// Returns [TaskInfo] with information about the created task
  Future<TaskInfo> request(HttpRequest request) async {
    return await _createRequest(request);
  }

  /// Internal method for creating a request
  Future<TaskInfo> _createRequest(HttpRequest request) async {
    final result = await _platform.createRequest(request.toJson());
    return TaskInfo.fromJson(result);
  }

  /// Gets task status by ID
  ///
  /// [requestId] - task ID
  ///
  /// Returns [TaskInfo] with task information or null if the task is not found
  Future<TaskInfo?> getRequestStatus(String requestId) async {
    final result = await _platform.getRequestStatus(requestId);
    if (result == null) {
      return null;
    }
    return TaskInfo.fromJson(result);
  }

  /// Gets the server response by task ID
  ///
  /// [requestId] - task ID
  ///
  /// Returns [TaskInfo] with response data (including responseJson) or null if the task is not found
  Future<TaskInfo?> getResponse(String requestId) async {
    final result = await _platform.getResponse(requestId);
    if (result == null) {
      return null;
    }
    return TaskInfo.fromJson(result);
  }

  /// Cancels a task by ID
  ///
  /// [requestId] - task ID to cancel
  ///
  /// Returns true if the task was cancelled, false if it could not be cancelled, null if the task does not exist
  Future<bool?> cancelRequest(String requestId) async {
    return await _platform.cancelRequest(requestId);
  }

  /// Deletes a task and all related files by ID
  ///
  /// [requestId] - task ID to delete
  ///
  /// Returns true if the task was deleted, false if it could not be deleted, null if the task does not exist
  ///
  /// Deletes:
  /// - All WorkManager tasks (Android) or active tasks (iOS)
  /// - Request file
  /// - Response file (JSON and data)
  /// - Status file
  /// - Request body file (if it exists)
  Future<bool?> deleteRequest(String requestId) async {
    return await _platform.deleteRequest(requestId);
  }

  /// Gets a stream with IDs of completed tasks
  ///
  /// Returns Stream<String> with IDs of tasks that have been successfully completed.
  /// Each time a task successfully completes (HTTP status 200-299), its ID is sent to the stream.
  Stream<String> getCompletedTasksStream() {
    return _platform.getCompletedTasksStream();
  }

  /// Gets a list of pending tasks with registration dates
  ///
  /// Returns a list of [PendingTask] with task IDs and their registration dates
  Future<List<PendingTask>> getPendingTasks() async {
    final result = await _platform.getPendingTasks();
    return result.map((json) => PendingTask.fromJson(json)).toList();
  }

  /// Cancels all tasks
  ///
  /// Returns the number of cancelled tasks
  Future<int> cancelAllTasks() async {
    return await _platform.cancelAllTasks();
  }

  // ============== Queue management methods ==============

  /// Gets task queue statistics
  ///
  /// Returns [QueueStats] with information about the queue state:
  /// - pendingCount: number of tasks in the queue (waiting to be executed)
  /// - activeCount: number of active tasks (currently executing)
  /// - maxConcurrent: maximum number of concurrent tasks
  /// - maxQueueSize: maximum queue size
  Future<QueueStats> getQueueStats() async {
    final result = await _platform.getQueueStats();
    return QueueStats.fromJson(result);
  }

  /// Sets the maximum number of concurrent tasks
  ///
  /// [count] - maximum number of concurrent tasks (minimum 1, default 30)
  ///
  /// If you increase the limit, the plugin will automatically start additional tasks from the queue.
  /// If you decrease the limit, currently active tasks will not be cancelled,
  /// but new ones will not start until the number of active tasks is less than the new limit.
  Future<bool> setMaxConcurrentTasks(int count) async {
    if (count < 1) {
      throw ArgumentError('count must be at least 1');
    }
    return await _platform.setMaxConcurrentTasks(count);
  }

  /// Sets the maximum queue size
  ///
  /// [size] - maximum queue size (minimum 1, default 10000)
  ///
  /// If the queue is full, new tasks will be rejected.
  Future<bool> setMaxQueueSize(int size) async {
    if (size < 1) {
      throw ArgumentError('size must be at least 1');
    }
    return await _platform.setMaxQueueSize(size);
  }

  /// Synchronizes the queue state with the actual task state
  ///
  /// Called to clean up "stuck" tasks:
  /// - Tasks that are marked as active but are not running in WorkManager
  /// - Tasks in the queue for which the request file does not exist
  ///
  /// Recommended to call on application startup.
  Future<bool> syncQueueState() async {
    return await _platform.syncQueueState();
  }

  /// Forces queue processing
  ///
  /// Starts pending tasks if there are free slots.
  /// Usually this happens automatically, but it can be called manually
  /// to start tasks immediately.
  Future<bool> processQueue() async {
    return await _platform.processQueue();
  }
}
