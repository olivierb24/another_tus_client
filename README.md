# Another TUS Client

[![Pub Version](https://img.shields.io/pub/v/another_tus_client)](https://pub.dev/packages/another_tus_client)  
[![Platforms](https://img.shields.io/badge/platforms-web%20%7C%20android%20%7C%20ios%20%7C%20desktop-lightgrey)](https://pub.dev/packages/another_tus_client)

A Dart client for resumable file uploads using the TUS protocol.  
Forked from [tus_client_dart](https://pub.dev/packages/tus_client_dart).

> **tus** is an HTTP‑based protocol for _resumable file uploads_.  
> It enables interruption (intentional or accidental) and later resumption of uploads without needing to restart from the beginning.

---

## Table of Contents

- [Usage Examples](#usage-examples)
  - [1. Creating a Client](#1-creating-a-client)
  - [2. Starting an Upload](#2-starting-an-upload)
  - [3. Pausing an Upload](#3-pausing-an-upload)
  - [4. Resuming an Upload](#4-resuming-an-upload)
  - [5. Canceling an Upload](#5-canceling-an-upload)
  - [6. Using TusFileStore (Native Platforms)](#6-using-tusfilestore-native-platforms)
  - [7. Using TusIndexedDBStore (Web)](#7-using-tusindexeddbstore-web)
  - [8. File Selection on Web](#8-file-selection-on-web)
- [Maintainers](#maintainers)


## Usage Examples

### 1. Creating a Client

```dart
import 'package:another_tus_client/another_tus_client.dart';
import 'package:cross_file/cross_file.dart';

final file = XFile("/path/to/my/pic.jpg");
final client = TusClient(
  file,  // Must be an XFile
  store: TusMemoryStore(), // Will not persist through device restarts. For persistent URL storage in memory see below
  maxChunkSize: 6 * 1024 * 1024, // 6MB chunks
  retries: 5,
  retryScale: RetryScale.exponential,
  retryInterval: 2,
);
```

### 2. Starting an Upload

```dart
await client.upload(
  uri: Uri.parse("https://your-tus-server.com/files/"),
  onStart: (TusClient client, Duration? estimate) {
    print("Upload started; estimated time: ${estimate?.inSeconds} seconds");
  },
  onProgress: (double progress, Duration estimate) {
    print("Progress: ${progress.toStringAsFixed(1)}%, estimated time: ${estimate.inSeconds} seconds");
  },
  onComplete: () {
    print("Upload complete!");
    print("File URL: ${client.uploadUrl}");
  },
  headers: {"Authorization": "Bearer your_token"},
  metadata: {"cacheControl": "3600"},
  measureUploadSpeed: true,
);
```

### 3. Pausing an Upload

Upload will pause after the current chunk finishes. For example:

```dart
  print("Pausing upload...");
  await client.pauseUpload();
```

### 4. Resuming an Upload

If the upload has been paused, you can resume using:

```dart
print("Resuming upload...");
await client.resumeUpload();
```

### 5. Canceling an Upload

Cancel the current upload and remove any saved state:

```dart
final result = await client.cancelUpload(); // Returns true when successful
if (result) {
  print("Upload canceled successfully.");
}
```

### 6. Using TusFileStore (Native Platforms)

On mobile/desktop, you can persist the upload progress to the file system.

```dart
import 'package:path_provider/path_provider.dart';
import 'dart:io';

final tempDir = await getTemporaryDirectory();
final tempDirectory = Directory('${tempDir.path}/${file.name}_uploads');
if (!tempDirectory.existsSync()) {
  tempDirectory.createSync(recursive: true);
}

final client = TusClient(
  file,
  store: TusFileStore(tempDirectory),
);
await client.upload(uri: Uri.parse("https://your-tus-server.com/files/"));
```

### 7. Using TusIndexedDBStore (Web)

For web applications, use IndexedDB for persistent upload state:

```dart
import 'package:flutter/foundation.dart' show kIsWeb;

final store = kIsWeb ? TusIndexedDBStore() : TusMemoryStore();

final client = TusClient(
  file,
  store: store,
);
await client.upload(uri: Uri.parse("https://your-tus-server.com/files/"));
```

### 8. File Selection on Web

For web applications, you have two main options for handling files:

#### Option 1: Using Any XFile with Loaded Bytes

```dart
import 'package:file_picker/file_picker.dart';

final result = await FilePicker.platform.pickFiles(
    withData: true, // Load bytes into memory. Works for small files
);

if (result == null) {
    return null;
}

final fileWithBytes = result.files.first.xFile; // This returns an XFile with bytes

// Create client with any XFile that has bytes loaded
final client = TusClient(
  fileWithBytes,  // Any XFile with bytes already loaded
  store: TusMemoryStore(), //This TusMemoryStore doesn't persist on reboots.
);

await client.upload(uri: Uri.parse("https://tus.example.com/files"));
```

#### Option 2: Using pickWebFilesForUpload()

This is a built-in method that will open a file picker on web and convert the files to a streamable XFile using Blob.


```dart
final result = await pickWebFilesForUpload(
    allowMultiple: true,
    acceptedFileTypes: ['*']  
)

if (result == null) {
    return null;
}

// Create client with any XFile that has bytes loaded
final client = TusClient(
  result.first,  // Streaming ready XFile
  store: TusMemoryStore(), 
);

await client.upload(uri: Uri.parse("https://tus.example.com/files"));
```

---

## Maintainers

- [Olivier Beaulieu](https://github.com/olivierb24)
