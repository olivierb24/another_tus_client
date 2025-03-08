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
  - [9. Using TusUploadManager](#9-using-tusuploadmanager)
  - [10. Persisting Upload Manager State](#10-persisting-upload-manager-state)
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
  preventDuplicates: true, // NEW: Prevents creating duplicate uploads of the same file
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
// Resume with the same callbacks as original upload
await client.resumeUpload();

// Resume with a new progress callback
await client.resumeUpload(
  onProgress: (progress, estimate) {
    print("New progress handler: $progress%");
  }
);

// Clear the progress callback while keeping others
await client.resumeUpload(
  clearProgressCallback: true
);

// Replace some callbacks and clear others
await client.resumeUpload(
  onComplete: () => print("New completion handler"),
  clearProgressCallback: true
);

// Clear all callbacks
await client.clearAllCallbacks();
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

### 9. Using TusUploadManager

The TusUploadManager provides a convenient way to manage multiple uploads with features like automatic queuing, status tracking, and batch operations.

#### Creating the Upload Manager

```dart
import 'package:another_tus_client/another_tus_client.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// Create a persistent store for upload state
final store = kIsWeb ? TusIndexedDBStore() : TusFileStore(await getUploadDirectory());

// Initialize the manager
final uploadManager = TusUploadManager(
  serverUrl: Uri.parse("https://your-tus-server.com/files/"),
  store: store,
  maxConcurrentUploads: 3,  // Control how many uploads run simultaneously
  autoStart: true,           // Start uploads as soon as they're added (default)
  measureUploadSpeed: true,  // Estimate upload time
  retries: 3,                // Retry failed uploads 3 times
  retryScale: RetryScale.exponential,
  retryInterval: 2,          // Wait 2, 4, 8 seconds between retries
  preventDuplicates: true,   // Prevent creating duplicate uploads
);
```

#### Adding Files to Upload

```dart
// Add a single file. Returns a custom ID for this upload
final uploadId1 = await uploadManager.addUpload(
  file1,
  metadata: {
    "bucketName": "user_files",
    "cacheControl": "3600",
    "contentType": file1.mimeType ?? "application/octet-stream"
  },
  headers: {
    "x-custom-header": "value"  // Add upload-specific headers
  }
);

// Add another file with different settings
final uploadId2 = await uploadManager.addUpload(
  file2,
  metadata: {"bucketName": "images"}
);
```

#### Listening to Upload Events

```dart
// Listen to upload status changes and progress updates
uploadManager.uploadEvents.listen((upload, event) {
  print("Upload ID: ${upload.id}");
  print("Event: ${event}"); // start, resume, pause, progress, complete, error, cancel, add
  print("Status: ${upload.status}");  // ready, uploading, paused, completed, failed, cancelled
  print("Progress: ${upload.progress}%");
  print("Estimated time: ${upload.estimate.inSeconds} seconds");
  
  if (upload.status == UploadStatus.completed) {
    print("Upload URL: ${upload.client.uploadUrl}");
  } else if (upload.status == UploadStatus.failed) {
    print("Error: ${upload.error}");
  }
});
```

#### Controlling Individual Uploads

```dart
// Pause a specific upload
await uploadManager.pauseUpload(uploadId1);

// Resume a paused upload
await uploadManager.resumeUpload(uploadId1);

// Cancel an upload
await uploadManager.cancelUpload(uploadId2);

// Check for specific upload
final upload = uploadManager.getUpload(uploadId1);
if (upload != null && upload.status == UploadStatus.paused) {
  // Check if it's resumable
  final isResumable = await upload.client.isResumable();
  print("Can resume: $isResumable");
}
```

#### Batch Operations

```dart
// Pause all active uploads
await uploadManager.pauseAll();

// Resume all paused uploads
await uploadManager.resumeAll();

// Cancel all uploads
await uploadManager.cancelAll();

// Get all uploads
final allUploads = uploadManager.getAllUploads();
print("Total uploads: ${allUploads.length}");
```

#### Cleanup

```dart
// Clean up resources when done
@override
void dispose() {
  uploadManager.dispose();
  super.dispose();
}
```

---

## Maintainers

- [Olivier Beaulieu](https://github.com/olivierb24)