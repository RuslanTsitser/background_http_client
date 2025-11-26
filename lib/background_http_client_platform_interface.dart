import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'background_http_client_method_channel.dart';

/// Абстрактный класс платформенного интерфейса для background_http_client
abstract class BackgroundHttpClientPlatform extends PlatformInterface {
  /// Конструктор платформенного интерфейса
  BackgroundHttpClientPlatform() : super(token: _token);

  static final Object _token = Object();

  static BackgroundHttpClientPlatform _instance = MethodChannelBackgroundHttpClient();

  /// Экземпляр [BackgroundHttpClientPlatform] по умолчанию
  ///
  /// По умолчанию используется [MethodChannelBackgroundHttpClient]
  static BackgroundHttpClientPlatform get instance => _instance;

  /// Платформенные реализации должны установить это значение
  /// своим собственным классом, расширяющим [BackgroundHttpClientPlatform]
  /// при регистрации
  static set instance(BackgroundHttpClientPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Создает HTTP запрос в нативном HTTP сервисе
  ///
  /// [requestJson] - JSON представление [HttpRequest]
  ///
  /// Возвращает JSON с [TaskInfo] (id, status, path, registrationDate)
  Future<Map<String, dynamic>> createRequest(Map<String, dynamic> requestJson) {
    throw UnimplementedError('createRequest() has not been implemented.');
  }

  /// Получает статус задачи по ID
  ///
  /// [requestId] - ID задачи
  ///
  /// Возвращает JSON с [TaskInfo] (id, status, path, registrationDate) или null, если задача не найдена
  Future<Map<String, dynamic>?> getRequestStatus(String requestId) {
    throw UnimplementedError('getRequestStatus() has not been implemented.');
  }

  /// Получает ответ от сервера по ID задачи
  ///
  /// [requestId] - ID задачи
  ///
  /// Возвращает JSON с [TaskInfo] (id, status, path, registrationDate, responseJson) или null, если задача не найдена
  Future<Map<String, dynamic>?> getResponse(String requestId) {
    throw UnimplementedError('getResponse() has not been implemented.');
  }

  /// Отменяет задачу по ID
  ///
  /// [requestId] - ID задачи для отмены
  ///
  /// Возвращает true если задача отменена, false если не получилось отменить, null если задачи не существует
  Future<bool?> cancelRequest(String requestId) {
    throw UnimplementedError('cancelRequest() has not been implemented.');
  }

  /// Удаляет задачу и все связанные файлы по ID
  ///
  /// [requestId] - ID задачи для удаления
  ///
  /// Возвращает true если задача удалена, false если не получилось удалить, null если задачи не существует
  Future<bool?> deleteRequest(String requestId) {
    throw UnimplementedError('deleteRequest() has not been implemented.');
  }

  /// Получает stream с ID завершенных задач
  ///
  /// Возвращает Stream<String> с ID задач, которые были успешно завершены (HTTP статус 200-299)
  Stream<String> getCompletedTasksStream() {
    throw UnimplementedError('getCompletedTasksStream() has not been implemented.');
  }
}
