import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'background_http_client_method_channel.dart';

/// Абстрактный класс платформенного интерфейса для background_http_client
abstract class BackgroundHttpClientPlatform extends PlatformInterface {
  /// Конструктор платформенного интерфейса
  BackgroundHttpClientPlatform() : super(token: _token);

  static final Object _token = Object();

  static BackgroundHttpClientPlatform _instance =
      MethodChannelBackgroundHttpClient();

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

  /// Выполняет HTTP запрос в фоновом режиме
  ///
  /// [requestJson] - JSON представление [HttpRequest]
  ///
  /// Возвращает JSON с [RequestInfo] (requestId и requestFilePath)
  Future<Map<String, dynamic>> executeRequest(
      Map<String, dynamic> requestJson) {
    throw UnimplementedError(
        'executeRequest() has not been implemented.');
  }

  /// Получает статус запроса по ID
  ///
  /// [requestId] - ID запроса
  ///
  /// Возвращает индекс статуса в enum [RequestStatus]
  Future<int> getRequestStatus(String requestId) {
    throw UnimplementedError(
        'getRequestStatus() has not been implemented.');
  }

  /// Получает ответ от сервера по ID запроса
  ///
  /// [requestId] - ID запроса
  ///
  /// Возвращает JSON с [HttpResponse] или null, если ответ еще не получен
  Future<Map<String, dynamic>?> getResponse(String requestId) {
    throw UnimplementedError('getResponse() has not been implemented.');
  }

  /// Отменяет запрос по ID
  ///
  /// [requestId] - ID запроса для отмены
  Future<void> cancelRequest(String requestId) {
    throw UnimplementedError('cancelRequest() has not been implemented.');
  }

  /// Удаляет запрос и все связанные файлы по ID
  ///
  /// [requestId] - ID запроса для удаления
  Future<void> deleteRequest(String requestId) {
    throw UnimplementedError('deleteRequest() has not been implemented.');
  }
}

/// Устаревший метод, оставлен для обратной совместимости
@Deprecated('Use BackgroundHttpClient methods instead')
extension BackgroundHttpClientDeprecated on BackgroundHttpClientPlatform {
  Future<String?> getPlatformVersion() {
    throw UnimplementedError(
        'getPlatformVersion() has been deprecated. Use BackgroundHttpClient methods instead.');
  }
}
