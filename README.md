# background_http_client

Плагин Flutter для выполнения HTTP запросов в фоновом режиме с интерфейсом, похожим на Dio.

## Особенности

- Интерфейс, похожий на Dio (GET, POST, PUT, DELETE, PATCH, HEAD)
- Выполнение запросов в фоновом режиме
- Сохранение запросов и ответов в файлы
- Отслеживание статуса запросов
- Получение ответов по ID запроса

## Использование

### Базовое использование

```dart
import 'package:background_http_client/background_http_client.dart';

final client = BackgroundHttpClient();

// GET запрос
final requestInfo = await client.get('https://api.example.com/data');

// POST запрос
final postInfo = await client.post(
  'https://api.example.com/data',
  data: {'key': 'value'},
);

// Получение статуса запроса
final status = await client.getRequestStatus(requestInfo.requestId);

// Получение ответа
final response = await client.getResponse(requestInfo.requestId);
if (response != null) {
  print('Status Code: ${response.statusCode}');
  print('Response File: ${response.responseFilePath}');
}
```

### Методы запросов

- `get(url, {headers, queryParameters, timeout, requestId, retries})` - GET запрос
- `post(url, {data, headers, queryParameters, timeout, requestId, retries})` - POST запрос
- `put(url, {data, headers, queryParameters, timeout, requestId, retries})` - PUT запрос
- `delete(url, {headers, queryParameters, timeout, requestId, retries})` - DELETE запрос
- `patch(url, {data, headers, queryParameters, timeout, requestId, retries})` - PATCH запрос
- `head(url, {headers, queryParameters, timeout, requestId, retries})` - HEAD запрос
- `postMultipart(url, {fields, files, headers, queryParameters, timeout, requestId, retries})` - Multipart запрос

### Повторные попытки (Retries)

Для автоматических повторных попыток при ошибках (таймауты, сетевые ошибки, ошибки сервера) используйте параметр `retries`:

```dart
// Запрос с 3 повторными попытками
final requestInfo = await client.get(
  'https://api.example.com/data',
  retries: 3, // От 0 до 10
);
```

**Как это работает:**

- При ошибке (таймаут, сетевые ошибки, HTTP статус >= 400) запрос автоматически повторяется
- Используется экспоненциальная задержка между попытками: 2, 4, 8, 16, 32, 64, 128, 256, 512 секунд (максимум 512)
- Статус запроса обновляется на "в процессе" во время ожидания повтора
- После исчерпания всех попыток запрос помечается как `FAILED`

### Обработка отсутствия интернета

**Android:**

- При отсутствии интернета WorkManager автоматически ждет появления сети благодаря `NetworkType.CONNECTED` constraint
- Задача будет автоматически выполнена, когда интернет появится, даже если приложение закрыто
- При сетевых ошибках (SocketException, ConnectException, UnknownHostException) задача автоматически повторяется при появлении сети

**iOS:**

- При отсутствии интернета URLSession автоматически обрабатывает сетевые ошибки
- Если приложение в фоне (свернуто), запрос будет автоматически повторен при появлении сети
- При полном закрытии приложения iOS может ограничивать выполнение задач

### Статусы запросов

- `RequestStatus.inProgress` - запрос в процессе выполнения
- `RequestStatus.completed` - получен ответ от сервера
- `RequestStatus.failed` - запрос завершился с ошибкой

## Архитектура

Плагин работает по следующему флоу:

1. Выполняется запрос через методы `get`, `post` и т.д.
2. Менеджер сохраняет файл для запроса, возвращает ID и путь к файлу
3. Менеджер ответственен за отправку, имеет 3 статуса: в процессе, получен ответ, ошибка
4. Ответ от сервера сохраняется в файле
5. По ID можно получить ответ от сервера и путь к файлу ответа

## Фоновая работа

### Android

- Использует **WorkManager** для выполнения запросов в фоне
- Запросы продолжают выполняться даже после закрытия приложения
- **Повторные попытки**: При использовании `retries` повторные попытки планируются через WorkManager с задержкой, что гарантирует их выполнение даже при закрытом приложении
- WorkManager автоматически управляет выполнением задач в фоне

### iOS

- Использует **URLSession с background configuration** для фоновой работы
- Запросы продолжают выполняться, когда приложение в фоне (свернуто)
- **Повторные попытки**: При использовании `retries` повторные попытки работают когда приложение в фоне (свернуто), но могут не работать при полном закрытии приложения
- **Важно**: После полного закрытия приложения iOS может ограничивать выполнение задач. Для гарантированной работы в фоне рекомендуется использовать приложение в свернутом состоянии, а не полностью закрывать его.

## Платформы

Плагин требует нативной реализации для Android и iOS. Метод канал `background_http_client` используется для коммуникации между Dart и нативным кодом.
