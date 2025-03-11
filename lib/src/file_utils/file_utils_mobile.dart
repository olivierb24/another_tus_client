import 'dart:async';
import 'package:cross_file/cross_file.dart';
import 'file_utils_interface.dart';

// Stub implementations for mobile platforms

/// Stub implementation for non-web platforms
Future<List<dynamic>> selectWebFiles({
  bool allowMultiple = false,
  List<String> acceptedFileTypes = const [],
}) async {
  throw UnsupportedError('selectWebFiles is only supported on web platforms');
}

/// Stub implementation for non-web platforms
XFile createXFileFromWebFile(dynamic file, {String? mimeType}) {
  throw UnsupportedError('createXFileFromWebFile is only supported on web platforms');
}

/// Stub implementation for non-web platforms
Future<List<XFile>?> pickWebFilesForUpload({
  bool allowMultiple = false,
  List<String> acceptedFileTypes = const [],
}) async {
  throw UnsupportedError('pickWebFilesForUpload is only supported on web platforms');
}