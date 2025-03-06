import 'dart:async';
import 'dart:developer';
import 'dart:math' show min;
import 'dart:typed_data' show Uint8List, BytesBuilder;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:speed_test_dart/speed_test_dart.dart';
import 'package:universal_io/io.dart';

import 'exceptions.dart';
import 'package:another_tus_client/src/retry_scale.dart';
import 'package:another_tus_client/src/tus_client_base.dart';

/// This class is used for creating or resuming uploads.
class TusClient extends TusClientBase {
  /// Create a new TusClient
  ///
  /// [file] An XFile instance representing the file to upload
  /// [store] Optional store for resumable uploads
  /// [maxChunkSize] Maximum size of chunks for upload (default: 512KB)
  /// [retries] Number of retries for failed uploads
  /// [retryScale] Scaling policy for retry intervals
  /// [retryInterval] Base interval between retries in milliseconds
  TusClient(
    XFile super.file, {
    super.store,
    super.maxChunkSize = 512 * 1024,
    super.retries = 0,
    super.retryScale = RetryScale.constant,
    super.retryInterval = 0,
  }) : _file = file {
    _fingerprint = generateFingerprint();
  }

  final XFile _file;

  /// The file being uploaded
  XFile get file => _file;

  /// Override this method to use a custom HTTP Client
  http.Client getHttpClient() => http.Client();

  int _actualRetry = 0;

  // Stored callbacks to be reused when resuming.
  Function(double, Duration)? _onProgress;
  Function()? _onComplete;

  /// Create a new [upload] throwing [ProtocolException] on server error
  Future<void> createUpload() async {
    try {
      if (_file.length is Function) {
        // For web when length is a function that returns Future<int>
        try {
          _fileSize = await (_file.length as dynamic)();
        } catch (e) {
          print("Error getting file size from function: $e");
          _fileSize = 0;
        }
      } else {
        // For mobile/desktop when length is a direct value
        _fileSize = _file.length as int?;
      }


      if (_fileSize == 0) {
        final content = await _file.readAsBytes();
        _fileSize = content.length;
      }

      final client = getHttpClient();
      final createHeaders = Map<String, String>.from(headers ?? {})
        ..addAll({
          "Tus-Resumable": tusVersion,
          "Upload-Metadata": _uploadMetadata ?? "",
          "Upload-Length": "$_fileSize",
        });

      final _url = url;

      if (_url == null) {
        throw ProtocolException('Error in request, URL is incorrect');
      }

      final response = await client.post(_url, headers: createHeaders);

      if (!(response.statusCode >= 200 && response.statusCode < 300) &&
          response.statusCode != 404) {
        throw ProtocolException(
            "Unexpected Error while creating upload", response.statusCode);
      }

      String urlStr = response.headers["location"] ?? "";
      if (urlStr.isEmpty) {
        throw ProtocolException(
            "missing upload Uri in response for creating upload");
      }

      _uploadUrl = _parseUrl(urlStr);
      store?.set(_fingerprint, _uploadUrl as Uri);
    } catch (e) {
      if (e is ProtocolException) rethrow;
      throw Exception('Cannot initiate file upload: $e');
    }
  }

  /// Check if the upload is resumable
  Future<bool> isResumable() async {
    try {
      _fileSize = _file.length as int?;
      _pauseUpload = false;

      if (!resumingEnabled) {
        return false;
      }

      _uploadUrl = await store?.get(_fingerprint);

      if (_uploadUrl == null) {
        return false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> setUploadTestServers() async {
    final tester = SpeedTestDart();

    try {
      final settings = await tester.getSettings();
      final servers = settings.servers;

      bestServers = await tester.getBestServers(
        servers: servers,
      );
    } catch (_) {
      bestServers = null;
    }
  }

  Future<void> uploadSpeedTest() async {
    final tester = SpeedTestDart();

    // If bestServers are null or they are empty, we will not measure upload speed
    // as it wouldn't be accurate at all
    if (bestServers == null || (bestServers?.isEmpty ?? true)) {
      uploadSpeed = null;
      return;
    }

    try {
      uploadSpeed = await tester.testUploadSpeed(servers: bestServers ?? []);
    } catch (_) {
      uploadSpeed = null;
    }
  }

  /// Start or resume an upload in chunks of [maxChunkSize] throwing
  /// [ProtocolException] on server error
  Future<void> upload({
    Function(double, Duration)? onProgress,
    Function(TusClient, Duration?)? onStart,
    Function()? onComplete,
    required Uri uri,
    Map<String, String>? metadata = const {},
    Map<String, String>? headers = const {},
    bool measureUploadSpeed = false,
  }) async {
    // Save the callbacks for possible resume.
    _onProgress = onProgress;
    _onComplete = onComplete;

    setUploadData(uri, headers, metadata);

    final _isResumable = await isResumable();

    if (measureUploadSpeed) {
      await setUploadTestServers();
      await uploadSpeedTest();
    }

    if (!_isResumable) {
      await createUpload();
    }

    // get offset from server
    _offset = await _getOffset();

    // Save the file size as an int in a variable to avoid having to call
    int totalBytes = _fileSize as int;

    // File existence check for non-web platforms before starting upload
    if (!kIsWeb && _file.path.isNotEmpty) {
      try {
        final file = File(_file.path);
        if (!file.existsSync()) {
          throw Exception("Cannot find file ${_file.path.split('/').last}");
        }
      } catch (e) {
        throw Exception("Cannot access file ${_file.path.split('/').last}: $e");
      }
    }

    // We start a stopwatch to calculate the upload speed
    final uploadStopwatch = Stopwatch()..start();

    // start upload
    final client = getHttpClient();

    if (onStart != null) {
      Duration? estimate;
      if (uploadSpeed != null) {
        final _workedUploadSpeed = uploadSpeed! * 1000000;

        estimate = Duration(
          seconds: (totalBytes / _workedUploadSpeed).round(),
        );
      }
      // The time remaining to finish the upload
      onStart(this, estimate);
    }

    while (!_pauseUpload && _offset < totalBytes) {
      // File existence check for non-web platforms before each chunk
      if (!kIsWeb && _file.path.isNotEmpty) {
        try {
          final file = File(_file.path);
          if (!file.existsSync()) {
            throw Exception("Cannot find file ${_file.path.split('/').last}");
          }
        } catch (e) {
          throw Exception(
              "Cannot access file ${_file.path.split('/').last}: $e");
        }
      }

      final uploadHeaders = Map<String, String>.from(headers ?? {})
        ..addAll({
          "Tus-Resumable": tusVersion,
          "Upload-Offset": "$_offset",
          "Content-Type": "application/offset+octet-stream"
        });

      await _performUpload(
        onComplete: onComplete,
        onProgress: onProgress,
        uploadHeaders: uploadHeaders,
        client: client,
        uploadStopwatch: uploadStopwatch,
        totalBytes: totalBytes,
      );
    }
  }

  Future<void> _performUpload({
    Function(double, Duration)? onProgress,
    Function()? onComplete,
    required Map<String, String> uploadHeaders,
    required http.Client client,
    required Stopwatch uploadStopwatch,
    required int totalBytes,
  }) async {
    try {
      final request = http.Request("PATCH", _uploadUrl as Uri)
        ..headers.addAll(uploadHeaders)
        ..bodyBytes = await _getData();
      _response = await client.send(request);

      if (_response != null) {
        _response?.stream.listen(
          (newBytes) {
            if (_actualRetry != 0) _actualRetry = 0;
          },
          onDone: () {
            if (onProgress != null && !_pauseUpload) {
              // Total byte sent
              final totalSent = _offset + maxChunkSize;
              double _workedUploadSpeed = 1.0;

              // If upload speed != null, it means it has been measured
              if (uploadSpeed != null) {
                // Multiplied by 10^6 to convert from Mb/s to b/s
                _workedUploadSpeed = uploadSpeed! * 1000000;
              } else {
                _workedUploadSpeed =
                    totalSent / uploadStopwatch.elapsedMilliseconds;
              }

              // The data that hasn't been sent yet
              final remainData = totalBytes - totalSent;
              final safeRemainData = remainData < 0 ? 0 : remainData;

              // The time remaining to finish the upload, clamped to 0
              final estimate = Duration(
                seconds: (safeRemainData / _workedUploadSpeed).round(),
              );

              final progress = totalSent / totalBytes * 100;

              try {
                onProgress((progress).clamp(0, 100), estimate);
              } catch (e) {
                log("Error in onProgress callback: $e");
              }

              _actualRetry = 0;
            }
          },
        );

        // check if correctly uploaded
        if (!(_response!.statusCode >= 200 && _response!.statusCode < 300)) {
          throw ProtocolException(
            "Error while uploading file",
            _response!.statusCode,
          );
        }

        int? serverOffset = _parseOffset(_response!.headers["upload-offset"]);
        if (serverOffset == null) {
          throw ProtocolException(
              "Response to PATCH request contains no or invalid Upload-Offset header");
        }
        if (_offset != serverOffset) {
          throw ProtocolException(
              "Response contains different Upload-Offset value ($serverOffset) than expected ($_offset)");
        }

        if (_offset == totalBytes && !_pauseUpload) {
          this.onCompleteUpload();
          if (onComplete != null) {
            try {
              onComplete();
            } catch (e) {
              log("Error in onComplete callback: $e");
            }
          }
        }
      } else {
        throw ProtocolException("Error getting Response from server");
      }
    } catch (e) {
      if (_actualRetry >= retries) rethrow;
      final waitInterval = retryScale.getInterval(
        _actualRetry,
        retryInterval,
      );
      _actualRetry += 1;
      log('Failed to upload, try: $_actualRetry, interval: $waitInterval');
      await Future.delayed(waitInterval);
      return await _performUpload(
        onComplete: onComplete,
        onProgress: onProgress,
        uploadHeaders: uploadHeaders,
        client: client,
        uploadStopwatch: uploadStopwatch,
        totalBytes: totalBytes,
      );
    }
  }

  /// Pause the current upload
  Future<bool> pauseUpload() async {
    try {
      _pauseUpload = true;
      await _response?.stream.timeout(Duration.zero);
      return true;
    } catch (e) {
      throw Exception("Error pausing upload");
    }
  }

  /// Resume the current upload from where it left off.
  Future<void> resumeUpload() async {
    try {
      // Set pause flag to false to allow the upload loop.
      _pauseUpload = false;
      // Re-fetch the server offset.
      _offset = await _getOffset();

      final totalBytes = _fileSize as int;
      final client = getHttpClient();
      final uploadStopwatch = Stopwatch()..start();

      while (!_pauseUpload && _offset < totalBytes) {
        final uploadHeaders = Map<String, String>.from(headers ?? {})
          ..addAll({
            "Tus-Resumable": tusVersion,
            "Upload-Offset": "$_offset",
            "Content-Type": "application/offset+octet-stream"
          });

        await _performUpload(
          onComplete: _onComplete,
          onProgress: _onProgress,
          uploadHeaders: uploadHeaders,
          client: client,
          uploadStopwatch: uploadStopwatch,
          totalBytes: totalBytes,
        );
      }
    } catch (e) {
      print("Error in resumeUpload: $e");
      throw Exception("Error resuming upload: $e");
    }
  }

  /// Cancel the current upload and remove it from the store
  Future<bool> cancelUpload() async {
    try {
      await pauseUpload();
      await store?.remove(_fingerprint);
      return true;
    } catch (_) {
      throw Exception("Error cancelling upload");
    }
  }

  /// Actions to be performed after a successful upload
  Future<void> onCompleteUpload() async {
    await store?.remove(_fingerprint);
  }

  /// Set the upload data for the client
  void setUploadData(
    Uri url,
    Map<String, String>? headers,
    Map<String, String>? metadata,
  ) {
    this.url = url;
    this.headers = headers;
    this.metadata = metadata;
    _uploadMetadata = generateMetadata();
  }

  /// Generate a fingerprint for the file
  @override
  String generateFingerprint() {
    try{
    //On mobile use path
    if (!kIsWeb && _file.path.isNotEmpty) {
      return "${_file.path}-${_file.name}-${_file.length}";
    } else {
      // On web, or when path is not available, use name and length
      return "${_file.name}-${DateTime.now().millisecondsSinceEpoch}";
    }
    } catch (e) {
      // If fails return signature from date
      return "tus-upload-${DateTime.now().millisecondsSinceEpoch}";
    }
  }

  /// Get offset from server throwing [ProtocolException] on error
  Future<int> _getOffset() async {
    final client = getHttpClient();

    final offsetHeaders = Map<String, String>.from(headers ?? {})
      ..addAll({
        "Tus-Resumable": tusVersion,
      });
    final response =
        await client.head(_uploadUrl as Uri, headers: offsetHeaders);

    if (!(response.statusCode >= 200 && response.statusCode < 300)) {
      throw ProtocolException(
        "Unexpected error while resuming upload",
        response.statusCode,
      );
    }

    int? serverOffset = _parseOffset(response.headers["upload-offset"]);
    if (serverOffset == null) {
      throw ProtocolException(
          "missing upload offset in response for resuming upload");
    }
    return serverOffset;
  }

  /// Get data from file to upload
  Future<Uint8List> _getData() async {
    int start = _offset;
    int end = _offset + maxChunkSize;
    end = end > (_fileSize ?? 0) ? _fileSize ?? 0 : end;

    // File existence check for non-web platforms before reading file
    if (!kIsWeb && _file.path.isNotEmpty) {
      try {
        final file = File(_file.path);
        if (!file.existsSync()) {
          throw Exception("Cannot find file ${_file.path.split('/').last}");
        }
      } catch (e) {
        throw Exception("Cannot access file ${_file.path.split('/').last}: $e");
      }
    }

    final result = BytesBuilder();

    // Use XFile's openRead to get a stream of the file content
    await for (final chunk in _file.openRead(start, end)) {
      result.add(chunk);
    }

    final bytesRead = min(maxChunkSize, result.length);
    _offset = _offset + bytesRead;

    return result.takeBytes();
  }

  int? _parseOffset(String? offset) {
    if (offset == null || offset.isEmpty) {
      return null;
    }
    if (offset.contains(",")) {
      offset = offset.substring(0, offset.indexOf(","));
    }
    return int.tryParse(offset);
  }

  Uri _parseUrl(String urlStr) {
    if (urlStr.contains(",")) {
      urlStr = urlStr.substring(0, urlStr.indexOf(","));
    }
    Uri uploadUrl = Uri.parse(urlStr);
    if (uploadUrl.host.isEmpty) {
      uploadUrl = uploadUrl.replace(host: url?.host, port: url?.port);
    }
    if (uploadUrl.scheme.isEmpty) {
      uploadUrl = uploadUrl.replace(scheme: url?.scheme);
    }
    return uploadUrl;
  }

  http.StreamedResponse? _response;

  int? _fileSize;

  String _fingerprint = "";

  String? _uploadMetadata;

  Uri? _uploadUrl;

  int _offset = 0;

  bool _pauseUpload = false;

  /// The URI on the server for the file
  Uri? get uploadUrl => _uploadUrl;

  /// The fingerprint of the file being uploaded
  String get fingerprint => _fingerprint;

  /// The 'Upload-Metadata' header sent to server
  String get uploadMetadata => _uploadMetadata ?? "";
}
