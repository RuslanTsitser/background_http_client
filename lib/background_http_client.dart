/// Plugin for executing HTTP requests in the background
///
/// This plugin allows you to perform standard HTTP requests (GET, POST, PUT, DELETE, PATCH, HEAD)
/// in the background. Requests are stored in files, and by ID you can retrieve their status and response.
library;

export 'src/background_http_client.dart';
export 'src/models.dart';
