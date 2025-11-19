import 'dart:async';
import 'dart:io';

import 'package:background_http_client/background_http_client.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _client = BackgroundHttpClient();
  final List<String> _logs = [];
  final ScrollController _scrollController = ScrollController();

  void _addLog(String message) {
    setState(() {
      final timestamp = DateTime.now().toString().substring(11, 19);
      _logs.add('[$timestamp] $message');
      // Автопрокрутка к последнему логу
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  Future<void> _executeGetRequest() async {
    try {
      _addLog('Выполняю GET запрос...');

      // Выполняем GET запрос
      final requestInfo = await _client.get('https://httpbin.org/get', queryParameters: {'test': 'value'});

      _addLog('Запрос создан');
      _addLog('  ID: ${requestInfo.requestId}');
      _addLog('  Путь к файлу запроса: ${requestInfo.requestFilePath}');

      // Периодически проверяем статус
      _pollRequestStatus(requestInfo.requestId);
    } catch (e) {
      _addLog('Ошибка при создании запроса: $e');
    }
  }

  Future<void> _executeGetRequestWithCustomId() async {
    try {
      _addLog('Выполняю GET запрос с кастомным ID...');

      // Выполняем GET запрос с кастомным ID
      final customId = 'my-custom-get-request-${DateTime.now().millisecondsSinceEpoch}';
      final requestInfo = await _client.get(
        'https://httpbin.org/get',
        queryParameters: {'customId': customId},
        requestId: customId,
      );

      _addLog('Запрос создан с кастомным ID');
      _addLog('  ID: ${requestInfo.requestId}');
      _addLog('  Путь к файлу запроса: ${requestInfo.requestFilePath}');

      // Периодически проверяем статус
      _pollRequestStatus(requestInfo.requestId);
    } catch (e) {
      _addLog('Ошибка при создании запроса: $e');
    }
  }

  Future<void> _executePostRequest() async {
    try {
      _addLog('Выполняю POST запрос...');

      // Выполняем POST запрос
      final requestInfo = await _client.post(
        'https://httpbin.org/post',
        data: {'message': 'Hello from background_http_client'},
        headers: {'Content-Type': 'application/json'},
      );

      _addLog('Запрос создан');
      _addLog('  ID: ${requestInfo.requestId}');
      _addLog('  Путь к файлу запроса: ${requestInfo.requestFilePath}');

      // Периодически проверяем статус
      _pollRequestStatus(requestInfo.requestId);
    } catch (e) {
      _addLog('Ошибка при создании запроса: $e');
    }
  }

  Future<void> _executeMultipartRequest() async {
    try {
      _addLog('Выполняю Multipart запрос...');

      // Создаем тестовый файл для загрузки
      final tempDir = await getTemporaryDirectory();
      final testFile = File('${tempDir.path}/test_file.txt');
      await testFile.writeAsString('Это тестовый файл для multipart запроса\nВремя создания: ${DateTime.now()}');

      if (!await testFile.exists()) {
        _addLog('Ошибка: не удалось создать тестовый файл');
        return;
      }

      _addLog('Тестовый файл создан: ${testFile.path}');

      // Выполняем multipart запрос
      final requestInfo = await _client.postMultipart(
        'https://httpbin.org/post',
        fields: {'description': 'Тестовый файл', 'category': 'example'},
        files: {'file': MultipartFile(filePath: testFile.path, filename: 'test_file.txt', contentType: 'text/plain')},
        requestId: 'multipart-request-${DateTime.now().millisecondsSinceEpoch}',
      );

      _addLog('Multipart запрос создан');
      _addLog('  ID: ${requestInfo.requestId}');
      _addLog('  Путь к файлу запроса: ${requestInfo.requestFilePath}');

      // Периодически проверяем статус
      _pollRequestStatus(requestInfo.requestId);
    } catch (e) {
      _addLog('Ошибка при создании multipart запроса: $e');
    }
  }

  Future<void> _executeLargeFileDownload() async {
    try {
      _addLog('Выполняю скачивание большого файла...');
      _addLog('(Потоковое скачивание для файлов > 100KB)');

      // Пример: скачивание большого файла
      // Используем кастомный ID для отслеживания
      final customId = 'large-file-download-${DateTime.now().millisecondsSinceEpoch}';
      final requestInfo = await _client.get(
        'https://httpbin.org/bytes/500000', // 500KB файл для теста
        requestId: customId,
      );

      _addLog('Запрос на скачивание большого файла создан');
      _addLog('  ID: ${requestInfo.requestId}');
      _addLog('  Путь к файлу запроса: ${requestInfo.requestFilePath}');
      _addLog('  Файл будет скачан потоково (не загружаясь полностью в память)');

      // Периодически проверяем статус
      _pollRequestStatus(requestInfo.requestId);
    } catch (e) {
      _addLog('Ошибка при создании запроса на скачивание: $e');
    }
  }

  Future<void> _pollRequestStatus(String requestId) async {
    Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      try {
        final status = await _client.getRequestStatus(requestId);
        final statusText = switch (status) {
          RequestStatus.inProgress => 'В процессе',
          RequestStatus.completed => 'Завершен',
          RequestStatus.failed => 'Ошибка',
        };

        if (status == RequestStatus.completed || status == RequestStatus.failed) {
          timer.cancel();

          // Получаем ответ
          final response = await _client.getResponse(requestId);
          if (response != null) {
            _addLog('Ответ получен');
            _addLog('  ID запроса: ${response.requestId}');
            _addLog('  Статус код: ${response.statusCode}');
            _addLog('  Статус: $statusText');
            if (response.responseFilePath != null) {
              _addLog('  Путь к файлу ответа: ${response.responseFilePath}');
            }
            if (response.body != null) {
              _addLog(
                '  Тело ответа (первые 200 символов): ${response.body!.length > 200 ? "${response.body!.substring(0, 200)}..." : response.body}',
              );
            }
            if (response.error != null) {
              _addLog('  Ошибка: ${response.error}');
            }
            _addLog('  Заголовки: ${response.headers.length} шт.');
          } else {
            _addLog('Ответ еще не получен');
          }
        }
      } catch (e) {
        timer.cancel();
        if (mounted) {
          _addLog('Ошибка при проверке статуса: $e');
        }
      }
    });
  }

  void _clearLogs() {
    setState(() {
      _logs.clear();
    });
  }

  Future<void> _openFile(String filePath) async {
    try {
      final file = File(filePath);

      if (!await file.exists()) {
        _addLog('Ошибка: файл не существует: $filePath');
        return;
      }

      _addLog('Открываю файл: $filePath');
      await OpenFile.open(filePath);
      _addLog('Файл открыт');
    } catch (e) {
      _addLog('Ошибка при открытии файла: $e');
    }
  }

  String? _extractFilePath(String log) {
    // Ищем паттерны: "Путь к файлу запроса: ..." или "Путь к файлу ответа: ..."
    final requestPathMatch = RegExp(r'Путь к файлу запроса: (.+)').firstMatch(log);
    if (requestPathMatch != null) {
      return requestPathMatch.group(1);
    }

    final responsePathMatch = RegExp(r'Путь к файлу ответа: (.+)').firstMatch(log);
    if (responsePathMatch != null) {
      return responsePathMatch.group(1);
    }

    return null;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Background HTTP Client Example'),
          actions: [IconButton(icon: const Icon(Icons.clear), onPressed: _clearLogs, tooltip: 'Очистить логи')],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(onPressed: _executeGetRequest, child: const Text('GET')),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _executeGetRequestWithCustomId,
                          child: const Text('GET (кастомный ID)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(onPressed: _executePostRequest, child: const Text('POST')),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(onPressed: _executeMultipartRequest, child: const Text('Multipart')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _executeLargeFileDownload,
                      child: const Text('Скачать большой файл (потоково)'),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Лог событий:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text('Записей: ${_logs.length}', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
              ),
            ),
            Expanded(
              child: _logs.isEmpty
                  ? Center(
                      child: Text('Логи будут отображаться здесь', style: TextStyle(color: Colors.grey[600])),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16.0),
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        final isError = log.contains('Ошибка');
                        final isRequestCreated = log.contains('Запрос создан');
                        final isResponseReceived = log.contains('Ответ получен');
                        final filePath = _extractFilePath(log);

                        final textStyle = TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: isError
                              ? Colors.red
                              : isRequestCreated
                              ? Colors.blue
                              : isResponseReceived
                              ? Colors.green
                              : Colors.black87,
                          fontWeight: isRequestCreated || isResponseReceived ? FontWeight.bold : FontWeight.normal,
                        );

                        if (filePath != null) {
                          // Если в логе есть путь к файлу, делаем его кликабельным
                          final pathIndex = log.indexOf(filePath);
                          final beforePath = log.substring(0, pathIndex);
                          final afterPath = log.substring(pathIndex + filePath.length);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4.0),
                            child: SelectableText.rich(
                              TextSpan(
                                style: textStyle,
                                children: [
                                  TextSpan(text: beforePath),
                                  TextSpan(
                                    text: filePath,
                                    style: textStyle.copyWith(color: Colors.blue, decoration: TextDecoration.underline),
                                    recognizer: TapGestureRecognizer()..onTap = () => _openFile(filePath),
                                  ),
                                  TextSpan(text: afterPath),
                                ],
                              ),
                            ),
                          );
                        }

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4.0),
                          child: SelectableText(log, style: textStyle),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
