import 'dart:async';
import 'dart:io';

import 'package:background_http_client/background_http_client.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MyApp());
}

class RequestItem {
  final String id;
  final String path;
  final DateTime registrationDate;
  String? responseFilePath;
  RequestStatus? status;
  Map<String, dynamic>? responseJson;

  RequestItem({
    required this.id,
    required this.path,
    required this.registrationDate,
    this.responseFilePath,
    this.status,
    this.responseJson,
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _client = BackgroundHttpClient();
  final List<RequestItem> _requests = [];
  Timer? _statusTimer;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _startStatusTimer();
  }

  void _startStatusTimer() {
    _statusTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      // Обновляем статусы только для запросов без ответа
      final pendingRequests = _requests.where((r) => r.responseFilePath == null).toList();

      if (pendingRequests.isEmpty) return;

      for (final request in pendingRequests) {
        try {
          final taskInfo = await _client.getRequestStatus(request.id);

          // Если задача не найдена - пропускаем
          if (taskInfo == null) {
            continue;
          }

          if (taskInfo.statusEnum == RequestStatus.completed || taskInfo.statusEnum == RequestStatus.failed) {
            final responseTaskInfo = await _client.getResponse(request.id);
            if (responseTaskInfo != null && mounted) {
              setState(() {
                request.status = responseTaskInfo.statusEnum;
                // Извлекаем responseFilePath из responseJson если есть
                if (responseTaskInfo.responseJson != null) {
                  final responseFilePath = responseTaskInfo.responseJson!['responseFilePath'] as String?;
                  if (responseFilePath != null && responseFilePath.isNotEmpty) {
                    request.responseFilePath = responseFilePath;
                  }
                }
                request.responseJson = responseTaskInfo.responseJson;
              });
            }
          } else if (mounted) {
            setState(() {
              request.status = taskInfo.statusEnum;
            });
          }
        } catch (e) {
          // Игнорируем ошибки при проверке статуса
        }
      }
    });
  }

  Future<void> _createGetRequest() async {
    try {
      final taskInfo = await _client.get('https://httpbin.org/get', queryParameters: {'test': 'value'});
      setState(() {
        _requests.add(
          RequestItem(
            id: taskInfo.id,
            path: taskInfo.path,
            registrationDate: taskInfo.registrationDateTime,
            status: taskInfo.statusEnum,
          ),
        );
      });
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      });
    } catch (e) {
      // Обработка ошибки
    }
  }

  Future<void> _createGetRequestWithCustomId() async {
    try {
      final customId = 'my-custom-get-request-${DateTime.now().millisecondsSinceEpoch}';
      final taskInfo = await _client.get(
        'https://httpbin.org/get',
        queryParameters: {'customId': customId},
        requestId: customId,
      );
      setState(() {
        _requests.add(
          RequestItem(
            id: taskInfo.id,
            path: taskInfo.path,
            registrationDate: taskInfo.registrationDateTime,
            status: taskInfo.statusEnum,
          ),
        );
      });
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      });
    } catch (e) {
      // Обработка ошибки
    }
  }

  Future<void> _createPostRequest() async {
    try {
      final taskInfo = await _client.post(
        'https://httpbin.org/post',
        data: {'message': 'Hello from background_http_client'},
        headers: {'Content-Type': 'application/json'},
      );
      setState(() {
        _requests.add(
          RequestItem(
            id: taskInfo.id,
            path: taskInfo.path,
            registrationDate: taskInfo.registrationDateTime,
            status: taskInfo.statusEnum,
          ),
        );
      });
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      });
    } catch (e) {
      // Обработка ошибки
    }
  }

  Future<void> _createMultipartRequest() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final testFile = File('${tempDir.path}/test_file.txt');
      await testFile.writeAsString('Это тестовый файл для multipart запроса\nВремя создания: ${DateTime.now()}');

      if (!await testFile.exists()) {
        return;
      }

      final taskInfo = await _client.postMultipart(
        'https://httpbin.org/post',
        fields: {'description': 'Тестовый файл', 'category': 'example'},
        files: {'file': MultipartFile(filePath: testFile.path, filename: 'test_file.txt', contentType: 'text/plain')},
        requestId: 'multipart-request-${DateTime.now().millisecondsSinceEpoch}',
      );
      setState(() {
        _requests.add(
          RequestItem(
            id: taskInfo.id,
            path: taskInfo.path,
            registrationDate: taskInfo.registrationDateTime,
            status: taskInfo.statusEnum,
          ),
        );
      });
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      });
    } catch (e) {
      // Обработка ошибки
    }
  }

  Future<void> _createLargeFileDownload() async {
    try {
      final customId = 'large-file-download-${DateTime.now().millisecondsSinceEpoch}';
      final taskInfo = await _client.get('https://httpbin.org/bytes/500000', requestId: customId);
      setState(() {
        _requests.add(
          RequestItem(
            id: taskInfo.id,
            path: taskInfo.path,
            registrationDate: taskInfo.registrationDateTime,
            status: taskInfo.statusEnum,
          ),
        );
      });
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      });
    } catch (e) {
      // Обработка ошибки
    }
  }

  void _clearRequests() {
    setState(() {
      _requests.clear();
    });
  }

  Future<void> _openFile(String filePath) async {
    try {
      await OpenFile.open(filePath);
    } catch (e) {
      // Обработка ошибки
    }
  }

  String _getStatusText(RequestStatus? status) {
    if (status == null) return 'Неизвестно';
    return switch (status) {
      RequestStatus.inProgress => 'В процессе',
      RequestStatus.completed => 'Завершен',
      RequestStatus.failed => 'Ошибка',
    };
  }

  Color _getStatusColor(RequestStatus? status) {
    if (status == null) return Colors.grey;
    return switch (status) {
      RequestStatus.inProgress => Colors.blue,
      RequestStatus.completed => Colors.green,
      RequestStatus.failed => Colors.red,
    };
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Background HTTP Client Example'),
          actions: [IconButton(icon: const Icon(Icons.clear), onPressed: _clearRequests, tooltip: 'Очистить список')],
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
                        child: ElevatedButton(onPressed: _createGetRequest, child: const Text('GET')),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _createGetRequestWithCustomId,
                          child: const Text('GET (кастомный ID)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(onPressed: _createPostRequest, child: const Text('POST')),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(onPressed: _createMultipartRequest, child: const Text('Multipart')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _createLargeFileDownload,
                      child: const Text('Скачать большой файл (потоково)'),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: _requests.isEmpty
                  ? const Center(child: Text('Список запросов пуст'))
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16.0),
                      itemCount: _requests.length,
                      itemBuilder: (context, index) {
                        final request = _requests[index];
                        return Card(
                          child: ListTile(
                            title: Text('ID: ${request.id}', style: const TextStyle(fontSize: 12)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  'Зарегистрировано: ${request.registrationDate.toString().substring(0, 19)}',
                                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                                ),
                                const SizedBox(height: 4),
                                TextButton(
                                  onPressed: () => _openFile(request.path),
                                  child: Text(
                                    'Запрос: ${request.path.split('/').last}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                if (request.responseFilePath != null) ...[
                                  const SizedBox(height: 4),
                                  TextButton(
                                    onPressed: () => _openFile(request.responseFilePath!),
                                    child: Text(
                                      'Ответ: ${request.responseFilePath?.split('/').last}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: _getStatusColor(request.status),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _getStatusText(request.status),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _getStatusColor(request.status),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
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
