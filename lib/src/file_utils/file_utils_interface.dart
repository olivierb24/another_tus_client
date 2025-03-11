import 'package:cross_file/cross_file.dart';

/// Controls debug logging throughout the file utilities.
const bool kTesting = false;

/// Function signature for file selection functionality
typedef WebFilesPicker = Future<List<XFile>?> Function({
  bool allowMultiple,
  List<String> acceptedFileTypes,
});

/// Interface for file utility functions
abstract class FileUtils {
  /// Picks files using the browser's file selector and converts them to XFiles.
  Future<List<XFile>?> pickWebFilesForUpload({
    bool allowMultiple = false,
    List<String> acceptedFileTypes = const [],
  });
}