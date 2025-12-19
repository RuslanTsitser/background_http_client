# background_http_client

Flutter plugin for executing HTTP requests in the background with a Dio-like interface.

## Features

- Dio-like interface (GET, POST, PUT, DELETE, PATCH, HEAD)
- Background request execution
- Saving requests and responses to files
- Request status tracking
- Getting responses by request ID

## Usage

### Basic Usage

```dart
import 'package:background_http_client/background_http_client.dart';

final client = BackgroundHttpClient();

// GET request
final requestInfo = await client.get('https://api.example.com/data');

// POST request
final postInfo = await client.post(
  'https://api.example.com/data',
  data: {'key': 'value'},
);

// Get request status
final status = await client.getRequestStatus(requestInfo.requestId);

// Get response
final response = await client.getResponse(requestInfo.requestId);
if (response != null) {
  print('Status Code: ${response.statusCode}');
  print('Response File: ${response.responseFilePath}');
}
```

### Request Methods

- `get(url, {headers, queryParameters, timeout, requestId, retries})` - GET request
- `post(url, {data, headers, queryParameters, timeout, requestId, retries})` - POST request
- `put(url, {data, headers, queryParameters, timeout, requestId, retries})` - PUT request
- `delete(url, {headers, queryParameters, timeout, requestId, retries})` - DELETE request
- `patch(url, {data, headers, queryParameters, timeout, requestId, retries})` - PATCH request
- `head(url, {headers, queryParameters, timeout, requestId, retries})` - HEAD request
- `postMultipart(url, {fields, files, headers, queryParameters, timeout, requestId, retries})` - Multipart request

### Retries

For automatic retries on errors (timeouts, network errors, server errors), use the `retries` parameter:

```dart
// Request with 3 retries
final requestInfo = await client.get(
  'https://api.example.com/data',
  retries: 3, // From 0 to 10
);
```

**How it works:**

- On error (timeout, network errors, HTTP status >= 400) the request is automatically retried
- Exponential backoff is used between retries: 2, 4, 8, 16, 32, 64, 128, 256, 512 seconds (max 512)
- Request status is updated to "in progress" during retry wait
- After all retries are exhausted, the request is marked as `FAILED`

### Handling No Internet Connection

**Android:**

- When there's no internet, WorkManager automatically waits for network availability thanks to `NetworkType.CONNECTED` constraint
- The task will be automatically executed when internet becomes available, even if the app is closed
- On network errors (SocketException, ConnectException, UnknownHostException) the task is automatically retried when network becomes available

**iOS:**

- When there's no internet, URLSession automatically handles network errors
- If the app is in background (minimized), the request will be automatically retried when network becomes available
- After complete app termination, iOS may limit task execution

### Request Statuses

- `RequestStatus.inProgress` - request is in progress
- `RequestStatus.completed` - response received from server
- `RequestStatus.failed` - request failed with error

## Architecture

The plugin works according to the following flow:

1. Request is executed via `get`, `post`, etc. methods
2. Manager saves a file for the request, returns ID and file path
3. Manager is responsible for sending, has 3 statuses: in progress, response received, error
4. Server response is saved to a file
5. By ID you can get the server response and path to the response file

## Background Work

### Android

- Uses **WorkManager** for executing requests in the background
- Requests continue to execute even after the app is closed
- **Retries**: When using `retries`, retry attempts are scheduled via WorkManager with delay, ensuring execution even when the app is closed
- WorkManager automatically manages task execution in the background

### iOS

- Uses **URLSession with background configuration** for background work
- Requests continue to execute when the app is in background (minimized)
- **Retries**: When using `retries`, retry attempts work when the app is in background (minimized), but may not work after complete app termination
- **Important**: After complete app termination, iOS may limit task execution. For guaranteed background work, it's recommended to keep the app minimized rather than completely closing it.

## Platforms

The plugin requires native implementation for Android and iOS. Method channel `background_http_client` is used for communication between Dart and native code.
