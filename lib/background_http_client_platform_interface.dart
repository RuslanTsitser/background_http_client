import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'background_http_client_method_channel.dart';

/// Abstract platform interface class for background_http_client
abstract class BackgroundHttpClientPlatform extends PlatformInterface {
  /// Platform interface constructor
  BackgroundHttpClientPlatform() : super(token: _token);

  static final Object _token = Object();

  static BackgroundHttpClientPlatform _instance =
      MethodChannelBackgroundHttpClient();

  /// Default instance of [BackgroundHttpClientPlatform]
  ///
  /// By default, [MethodChannelBackgroundHttpClient] is used.
  static BackgroundHttpClientPlatform get instance => _instance;

  /// Platform implementations should set this value
  /// to their own class that extends [BackgroundHttpClientPlatform]
  /// when registering.
  static set instance(BackgroundHttpClientPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Creates an HTTP request in the native HTTP service
  ///
  /// [requestJson] - JSON representation of [HttpRequest]
  ///
  /// Returns JSON with [TaskInfo] (id, status, path, registrationDate)
  Future<Map<String, dynamic>> createRequest(Map<String, dynamic> requestJson) {
    throw UnimplementedError('createRequest() has not been implemented.');
  }

  /// Gets task status by ID
  ///
  /// [requestId] - task ID
  ///
  /// Returns JSON with [TaskInfo] (id, status, path, registrationDate) or null if the task is not found
  Future<Map<String, dynamic>?> getRequestStatus(String requestId) {
    throw UnimplementedError('getRequestStatus() has not been implemented.');
  }

  /// Gets server response by task ID
  ///
  /// [requestId] - task ID
  ///
  /// Returns JSON with [TaskInfo] (id, status, path, registrationDate, responseJson) or null if the task is not found
  Future<Map<String, dynamic>?> getResponse(String requestId) {
    throw UnimplementedError('getResponse() has not been implemented.');
  }

  /// Cancels a task by ID
  ///
  /// [requestId] - task ID to cancel
  ///
  /// Returns true if the task was cancelled, false if it could not be cancelled, null if the task does not exist
  Future<bool?> cancelRequest(String requestId) {
    throw UnimplementedError('cancelRequest() has not been implemented.');
  }

  /// Deletes a task and all related files by ID
  ///
  /// [requestId] - task ID to delete
  ///
  /// Returns true if the task was deleted, false if it could not be deleted, null if the task does not exist
  Future<bool?> deleteRequest(String requestId) {
    throw UnimplementedError('deleteRequest() has not been implemented.');
  }

  /// Gets a stream with IDs of completed tasks
  ///
  /// Returns [Stream] of [String] with IDs of tasks that have been successfully completed (HTTP status 200-299)
  Stream<String> getCompletedTasksStream() {
    throw UnimplementedError(
        'getCompletedTasksStream() has not been implemented.');
  }

  /// Gets a list of pending tasks with registration dates
  ///
  /// Returns a list of [PendingTask] with task IDs and their registration dates
  Future<List<Map<String, dynamic>>> getPendingTasks() {
    throw UnimplementedError('getPendingTasks() has not been implemented.');
  }

  /// Cancels all tasks
  ///
  /// Returns the number of cancelled tasks
  Future<int> cancelAllTasks() {
    throw UnimplementedError('cancelAllTasks() has not been implemented.');
  }

  /// Gets task queue statistics
  ///
  /// Returns a Map with fields: pendingCount, activeCount, maxConcurrent, maxQueueSize
  Future<Map<String, dynamic>> getQueueStats() {
    throw UnimplementedError('getQueueStats() has not been implemented.');
  }

  /// Sets the maximum number of concurrent tasks
  ///
  /// [count] - maximum number of concurrent tasks (minimum 1)
  Future<bool> setMaxConcurrentTasks(int count) {
    throw UnimplementedError(
        'setMaxConcurrentTasks() has not been implemented.');
  }

  /// Sets the maximum queue size
  ///
  /// [size] - maximum queue size (minimum 1)
  Future<bool> setMaxQueueSize(int size) {
    throw UnimplementedError('setMaxQueueSize() has not been implemented.');
  }

  /// Synchronizes the queue state with the actual task state
  ///
  /// Called to clean up "stuck" tasks
  Future<bool> syncQueueState() {
    throw UnimplementedError('syncQueueState() has not been implemented.');
  }

  /// Forces queue processing
  ///
  /// Starts pending tasks if there are free slots
  Future<bool> processQueue() {
    throw UnimplementedError('processQueue() has not been implemented.');
  }
}
