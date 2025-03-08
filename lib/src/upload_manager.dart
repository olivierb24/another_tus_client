import 'dart:async';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:another_tus_client/another_tus_client.dart';

/// Status of an upload managed by [TusUploadManager]
enum UploadStatus {
  /// Upload is ready but not started
  ready,

  /// Upload is in progress
  uploading,

  /// Upload is paused
  paused,

  /// Upload is completed
  completed,

  /// Upload failed with an error
  failed,

  /// Upload was canceled
  cancelled
}

enum UploadEventType {
  add,
  start,
  progress,
  pause,
  resume,
  complete,
  error,
  cancel
}

/// Information about a managed upload
class ManagedUpload {
  /// Unique ID for this upload
  final String id;

  /// The TusClient instance handling this upload
  final TusClient client;

  /// Current status of the upload
  UploadStatus status;

  /// Progress from 0.0 to 100.0
  double progress;

  /// Estimated time remaining
  Duration estimate;

  /// Error message if status is [UploadStatus.failed]
  String? error;

  /// Created timestamp
  final DateTime createdAt;

  /// Last updated timestamp
  DateTime updatedAt;

  /// Headers for this upload
  final Map<String, String>? headers;

  /// Metadata for this upload
  final Map<String, String>? metadata;

  ManagedUpload({
    required this.id,
    required this.client,
    this.status = UploadStatus.ready,
    this.progress = 0.0,
    this.estimate = Duration.zero,
    this.error,
    this.headers,
    this.metadata,
  })  : createdAt = DateTime.now(),
        updatedAt = DateTime.now();

  /// Update the upload status and timestamps
  void updateStatus(UploadStatus newStatus, {String? errorMessage}) {
    status = newStatus;
    updatedAt = DateTime.now();
    if (errorMessage != null) {
      error = errorMessage;
    }
  }

  /// Update the progress and estimated time
  void updateProgress(double newProgress, Duration newEstimate) {
    progress = newProgress;
    estimate = newEstimate;
    updatedAt = DateTime.now();
  }
}

class UploadEvent {
  final ManagedUpload upload;
  final UploadEventType eventType;

  UploadEvent({required this.upload, required this.eventType});
}

/// Manager for handling multiple TUS uploads
class TusUploadManager {
  /// TUS server endpoint URL
  final Uri serverUrl;

  /// Store for persisting upload information
  final TusStore store;

  /// Default chunk size for all uploads in bytes (default: 5MB)
  final int defaultChunkSize;

  /// Maximum concurrent uploads (default: 3)
  final int maxConcurrentUploads;

  /// Whether to automatically start uploads when added (default: true)
  final bool autoStart;

  /// Whether to measure upload speed for better time estimates (default: true)
  final bool measureUploadSpeed;

  /// Whether to prevent duplicate uploads (default: true)
  final bool preventDuplicates;

  /// Retry settings for failed uploads
  final int retries;
  final RetryScale retryScale;
  final int retryInterval;

  /// Stream controller for upload events
  final StreamController<UploadEvent> _uploadEvents =
      StreamController<UploadEvent>.broadcast();

  /// Map of all managed uploads
  final Map<String, ManagedUpload> _uploads = {};

  /// Queue of uploads waiting to start
  final List<String> _queue = [];

  /// Set of currently active upload IDs
  final Set<String> _activeUploads = {};

  Stream<UploadEvent> get uploadEvents => _uploadEvents.stream;

  /// Constructor
  TusUploadManager({
    required this.serverUrl,
    required this.store,
    this.defaultChunkSize = 5 * 1024 * 1024,
    this.maxConcurrentUploads = 3,
    this.autoStart = true,
    this.measureUploadSpeed = true,
    this.preventDuplicates = true,
    this.retries = 3,
    this.retryScale = RetryScale.exponential,
    this.retryInterval = 2,
  });

  /// Add a new file for upload
  /// Returns the ID of the managed upload
  Future<String> addUpload(
    XFile file, {
    Map<String, String>? metadata,
    Map<String, String>? headers,
    int? chunkSize,
  }) async {
    // Create a unique ID for this upload based on file attributes
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final id = '${file.name}-$timestamp';

    // Create a TusClient for this file
    final client = TusClient(
      file,
      store: store,
      maxChunkSize: chunkSize ?? defaultChunkSize,
      retries: retries,
      retryScale: retryScale,
      retryInterval: retryInterval,
    );

    // Create managed upload object
    final upload = ManagedUpload(
      id: id,
      client: client,
      status: UploadStatus.ready,
      headers: headers, // Store for later reference
      metadata: metadata, // Store for later reference
    );

    // Add to our managed uploads
    _uploads[id] = upload;

    // Emit event
    _uploadEvents
        .add(UploadEvent(upload: upload, eventType: UploadEventType.add));

    // Auto-start if enabled
    if (autoStart) {
      await startUpload(id);
    } else {
      _queue.add(id);
    }

    return id;
  }

  /// Start a specific upload by ID
  Future<void> startUpload(String id) async {
    final upload = _uploads[id];
    if (upload == null) {
      throw Exception('Upload not found: $id');
    }

    // Don't start if already uploading
    if (upload.status == UploadStatus.uploading) {
      return;
    }

    // Check if we've reached max concurrent uploads
    if (_activeUploads.length >= maxConcurrentUploads) {
      // Add to queue if not already there
      if (!_queue.contains(id)) {
        _queue.add(id);
      }
      return;
    }

    // Mark as active
    _activeUploads.add(id);

    // Remove from queue if present
    _queue.remove(id);

    // Update status
    upload.updateStatus(UploadStatus.uploading);

    try {
      await upload.client.upload(
        uri: serverUrl,
        headers: upload.headers,
        metadata: upload.metadata,
        measureUploadSpeed: measureUploadSpeed,
        preventDuplicates: preventDuplicates,
        onStart: (client, estimate) {
          upload.updateStatus(UploadStatus.uploading);
          _uploadEvents.add(
              UploadEvent(upload: upload, eventType: UploadEventType.start));
        },
        onProgress: (progress, estimate) {
          upload.updateProgress(progress, estimate);
          _uploadEvents.add(
              UploadEvent(upload: upload, eventType: UploadEventType.progress));
        },
        onComplete: () {
          upload.updateStatus(UploadStatus.completed);
          upload.updateProgress(100, Duration.zero);
          _uploadEvents.add(
              UploadEvent(upload: upload, eventType: UploadEventType.complete));
          _activeUploads.remove(id);
          _processQueue();
        },
      );
    } catch (e) {
      upload.updateStatus(UploadStatus.failed, errorMessage: e.toString());
      _uploadEvents
          .add(UploadEvent(upload: upload, eventType: UploadEventType.error));
      _activeUploads.remove(id);
      _processQueue();
    }
  }

  /// Pause an upload
  Future<bool> pauseUpload(String id) async {
    final upload = _uploads[id];
    if (upload == null || upload.status != UploadStatus.uploading) {
      return false;
    }

    final result = await upload.client.pauseUpload();
    if (result) {
      upload.updateStatus(UploadStatus.paused);
      _uploadEvents
          .add(UploadEvent(upload: upload, eventType: UploadEventType.pause));
      _activeUploads.remove(id);
      _processQueue();
    }
    return result;
  }

  /// Resume a paused upload
  Future<void> resumeUpload(String id) async {
    final upload = _uploads[id];
    if (upload == null || upload.status != UploadStatus.paused) {
      return;
    }

    // If we've reached max concurrent uploads, add to queue
    if (_activeUploads.length >= maxConcurrentUploads) {
      if (!_queue.contains(id)) {
        _queue.add(id);
      }
      return;
    }

    // Mark as active
    _activeUploads.add(id);

    // Update status
    upload.updateStatus(UploadStatus.uploading);
    UploadEvent(upload: upload, eventType: UploadEventType.resume);
    try {
      await upload.client.resumeUpload(
        onProgress: (progress, estimate) {
          upload.updateProgress(progress, estimate);
          _uploadEvents.add(
              UploadEvent(upload: upload, eventType: UploadEventType.progress));
        },
        onComplete: () {
          upload.updateStatus(UploadStatus.completed);
          upload.updateProgress(100, Duration.zero);
          _uploadEvents.add(
              UploadEvent(upload: upload, eventType: UploadEventType.complete));
          _activeUploads.remove(id);
          _processQueue();
        },
      );
    } catch (e) {
      upload.updateStatus(UploadStatus.failed, errorMessage: e.toString());
      _uploadEvents
          .add(UploadEvent(upload: upload, eventType: UploadEventType.error));
      _activeUploads.remove(id);
      _processQueue();
    }
  }

  /// Cancel an upload
  Future<bool> cancelUpload(String id) async {
    final upload = _uploads[id];
    if (upload == null) {
      return false;
    }

    bool result = true;
    if (upload.status == UploadStatus.uploading) {
      result = await upload.client.cancelUpload();
    }

    if (result) {
      upload.updateStatus(UploadStatus.cancelled);
      _uploadEvents
          .add(UploadEvent(upload: upload, eventType: UploadEventType.cancel));
      _uploads.remove(id);
      _activeUploads.remove(id);
      _queue.remove(id);
      _processQueue();
    }

    return result;
  }

  /// Get all managed uploads
  List<ManagedUpload> getAllUploads() {
    return _uploads.values.toList();
  }

  /// Get a specific upload by ID
  ManagedUpload? getUpload(String id) {
    return _uploads[id];
  }

  /// Pause all active uploads
  Future<void> pauseAll() async {
    // Create a copy of activeUploads to avoid modification during iteration
    final activeIds = List<String>.from(_activeUploads);
    for (final id in activeIds) {
      await pauseUpload(id);
    }
  }

  /// Resume all paused uploads
  Future<void> resumeAll() async {
    final pausedUploads = _uploads.values
        .where((upload) => upload.status == UploadStatus.paused)
        .map((upload) => upload.id)
        .toList();

    for (final id in pausedUploads) {
      // This will add to queue if we've reached max concurrent uploads
      await resumeUpload(id);
    }
  }

  /// Cancel all uploads
  Future<void> cancelAll() async {
    final uploadIds = List<String>.from(_uploads.keys);
    for (final id in uploadIds) {
      await cancelUpload(id);
    }
  }

  /// Process the upload queue
  void _processQueue() {
    // Start uploads from the queue if we have capacity
    while (_activeUploads.length < maxConcurrentUploads && _queue.isNotEmpty) {
      final id = _queue.removeAt(0);
      // Don't await to allow concurrent processing
      startUpload(id).catchError((e) {
        print('Error starting queued upload $id: $e');
      });
    }
  }

  /// Clean up resources
  void dispose() {
    _uploadEvents.close();
  }
}
