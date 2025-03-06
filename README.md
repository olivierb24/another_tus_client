# A tus client

[![Pub Version](https://img.shields.io/pub/v/another_tus_client)](https://pub.dev/packages/another_tus_client)
[![Platforms](https://img.shields.io/badge/platforms-web%20%7C%20android%20%7C%20ios%20%7C%20desktop-lightgrey)](https://pub.dev/packages/another_tus_client)
---

A tus client in dart with support for web. [Resumable uploads using tus protocol](https://tus.io/)
Forked from [tus_client_dart](https://pub.dev/packages/tus_client_dart)

> **tus** is a protocol based on HTTP for _resumable file uploads_. Resumable
> means that an upload can be interrupted at any moment and can be resumed without
> re-uploading the previous data again. An interruption may happen willingly, if
> the user wants to pause, or by accident in case of a network issue or server
> outage.

- [A tus client](#a-tus-client)
  - [Usage](#usage)
    - [Using Persistent URL Store](#using-persistent-url-store)
    - [Using IndexedDB Store for Web](#using-indexeddb-store-for-web)
    - [Handling Files from File Picker on Web](#handling-files-from-file-picker-on-web)
    - [Adding Extra Headers](#adding-extra-headers)
    - [Adding extra data](#adding-extra-data)
    - [Changing chunk size](#changing-chunk-size)
    - [Pausing upload](#pausing-upload)
    - [Set up the retry mechanism](#set-up-the-retry-mechanism)
  - [Example](#example)
  - [Maintainers](#maintainers)

## Usage

```dart
import 'package:cross_file/cross_file.dart' show XFile;

// File to be uploaded
final file = XFile("/path/to/my/pic.jpg");

// Create a client
final client = TusClient(
    file,
    store: TusMemoryStore(),
);

// Starts the upload
await client.upload(
    uri: Uri.parse("https://master.tus.io/files/"),
    onStart:(TusClient client, Duration? estimate){
        // If estimate is not null, it will provide the estimate time for completion
        // it will only be not null if measuring upload speed
        print('This is the client to be used $client and $estimate time');
    },
    onComplete: () {
        print("Complete!");

        // Prints the uploaded file URL
        print(client.uploadUrl.toString());
    },
    onProgress: (double progress, Duration estimate) {
        print("Progress: $progress, Estimated time: ${estimate.inSeconds}");
    },

    // Set this to true if you want to measure upload speed at the start of the upload
    measureUploadSpeed: true,
);
```

### Using Persistent URL Store

This is only supported on Flutter Android, iOS, Desktop.
You need to add to your `pubspec.yaml`:

```dart
import 'package:path_provider/path_provider.dart';

//creates temporal directory to store the upload progress
final tempDir = await getTemporaryDirectory();
final tempDirectory = Directory('${tempDir.path}/${gameId}_uploads');
if (!tempDirectory.existsSync()) {
    tempDirectory.createSync(recursive: true);
}

// Create a client
final client = TusClient(
    file,
    store: TusFileStore(tempDirectory),
);

// Start upload
// Don't forget to delete the tempDirectory
await client.upload(uri: Uri.parse("https://example.com/tus"));
```

### Using IndexedDB Store for Web

For web applications, use the `TusIndexedDBStore` for persistent uploads:

```dart
import 'package:flutter/foundation.dart' show kIsWeb;

// Choose appropriate store based on platform
final store = kIsWeb 
    ? TusIndexedDBStore() 
    : TusFileStore(await getTemporaryDirectory());

final client = TusClient(
    file,
    store: store,
);

await client.upload(uri: Uri.parse("https://tus.example.com/files"));
```

### Web File Uploads

For web applications, you have two main options for handling files:

#### Option 1: Using Any XFile with Loaded Bytes

```dart

// Create client with any XFile that has bytes loaded
final client = TusClient(
  xFile,  // Any XFile with bytes already loaded
  store: TusMemoryStore(), //This TusMemoryStore doesn't persist on reboots.
);

await client.upload(uri: Uri.parse("https://tus.example.com/files"));
```

#### Option 2: Using File Picker with Our Converter

```dart
import 'package:file_picker/file_picker.dart';

// 1. Pick a file
final result = await FilePicker.platform.pickFiles(
  withData: false,   
  withReadStream: true, // Required for proper streaming on web
);

if (result != null && result.files.isNotEmpty) {
  // 2. Convert to a streaming-capable XFile by passing platformFile to our XFileFactory.fromPlatformFile method
  final xFile = XFileFactory.fromPlatformFile(result.files.first);
  
  // 3. Upload with tus client
  final client = TusClient(
    xFile,
    store: kIsWeb ? TusIndexedDBStore() : TusMemoryStore(),
  );
  
  await client.upload(uri: Uri.parse("https://tus.example.com/files"));
}
```

Our converter ensures that both large files (streaming) and small files (in-memory) work correctly on web.


### Adding Extra Headers

```dart
final client = TusClient(
    file,
    headers: {"Authorization": "..."},
);

await client.upload(uri: Uri.parse("https://master.tus.io/files/"));
```

### Adding extra data

```dart
final client = TusClient(
    file,
    metadata: {"for-gallery": "..."},
);

await client.upload(uri: Uri.parse("https://master.tus.io/files/"));
```

### Changing chunk size

The file is uploaded in chunks. Default size is 512KB. This should be set considering `speed of upload` vs `device memory constraints`

```dart
final client = TusClient(
    file,
    maxChunkSize: 10 * 1024 * 1024,  // chunk is 10MB
);

await client.upload(uri: Uri.parse("https://master.tus.io/files/"));
```

### Pausing upload

Pausing upload can be done after current uploading in chunk is completed.

```dart
final client = TusClient(
    file
);

// Pause after 5 seconds
Future.delayed(Duration(seconds: 5)).then((_) => client.pauseUpload());

// Starts the upload
await client.upload(
    uri: Uri.parse("https://master.tus.io/files/"),
    onComplete: () {
        print("Complete!");
    },
    onProgress: (double progress, Duration estimate) {
        print("Progress: $progress, Estimated time: ${estimate.inSeconds}");
    },
);
```

### Set up the retry mechanism

It is posible to set up how many times the upload can fail before throw an error to increase robustness of the upload.
Just indicate how many retries to set up the number of attempts before fail, the retryInterval (in seconds) to indicate the time between every retry
and the retryScale (constant by default) to indicate how this time should increase or not between every retry.

```dart
final client = TusClient(
    file,
    retries: 5,
    retryInterval: 2,
    retryScale: RetryScale.exponential,
);

await client.upload(uri: Uri.parse("https://master.tus.io/files/"));
```

## Example

For an example of usage in a Flutter app (using file picker) see: [/example](https://github.com/tomassasovsky/tus_client/tree/master/example/lib/main.dart)

## Maintainers

- [Olivier Beaulieu](https://github.com/olivierb24)