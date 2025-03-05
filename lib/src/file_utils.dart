import 'dart:async';
import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// XFile implementation that supports proper streaming on web
class StreamXFileWeb extends XFile {
  final PlatformFile _platformFile;
  
  StreamXFileWeb(this._platformFile, {String? mimeType})
      : super(
          '',
          name: _platformFile.name,
          length: _platformFile.size,
          mimeType: mimeType,
        );
  
  @override
  Stream<Uint8List> openRead([int? start, int? end]) {
    final Stream<List<int>>? baseStream = _platformFile.readStream;
    if (baseStream == null) {
      throw UnsupportedError('No readStream available for this file');
    }
    // If no range specified, simply convert the stream to emit Uint8List.
    if ((start == null || start == 0) && end == null) {
      return baseStream.map((chunk) {
        if (chunk is Uint8List) return chunk;
        return Uint8List.fromList(chunk);
      });
    }
    final int fileSize = _platformFile.size;
    final int from = start ?? 0;
    final int to = (end != null && end < fileSize) ? end : fileSize - 1;
    if (from > to) {
      return const Stream<Uint8List>.empty();
    }
    // Create a controller to emit only the requested byte range.
    late StreamSubscription<List<int>> sub;
    final controller = StreamController<Uint8List>();
    // How many bytes to skip and take from the stream.
    int bytesToSkip = from;
    int bytesToSend = to - from + 1;
    sub = baseStream.listen(
      (chunk) {
        // Convert chunk to Uint8List if needed.
        Uint8List uChunk =
            chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
        // Skip initial bytes if necessary.
        if (bytesToSkip > 0) {
          if (uChunk.length <= bytesToSkip) {
            bytesToSkip -= uChunk.length;
            return; // skip entire chunk
          } else {
            uChunk = uChunk.sublist(bytesToSkip);
            bytesToSkip = 0;
          }
        }
        // If an end offset is specified, emit only the remaining needed bytes.
        if (end != null) {
          if (uChunk.length > bytesToSend) {
            controller.add(uChunk.sublist(0, bytesToSend));
            bytesToSend = 0;
            controller.close();
            sub.cancel();
          } else {
            controller.add(uChunk);
            bytesToSend -= uChunk.length;
            if (bytesToSend == 0) {
              controller.close();
              sub.cancel();
            }
          }
        } else {
          // No end specified; output the entire chunk.
          controller.add(uChunk);
        }
      },
      onDone: () {
        controller.close();
      },
      onError: (error, stack) {
        controller.addError(error, stack);
      },
      cancelOnError: true,
    );
    // Ensure that if the controller is cancelled, we cancel the underlying subscription.
    controller.onCancel = () {
      sub.cancel();
    };
    return controller.stream;
  }
}

/// Factory to create XFile instances that work on all platforms
class XFileFactory {
  /// Creates an XFile from a PlatformFile
  /// 
  /// On web, this returns a StreamXFileWeb that properly supports streaming
  /// On mobile, this returns a regular XFile
  static XFile fromPlatformFile(PlatformFile platformFile) {
    if (kIsWeb) {
      return StreamXFileWeb(platformFile, mimeType: platformFile.extension != null 
          ? _getMimeType(platformFile.extension!) 
          : null);
    } else {
      // On mobile, path should be available
      return XFile(platformFile.path ?? '',
          name: platformFile.name,
          length: platformFile.size,
          mimeType: platformFile.extension != null 
              ? _getMimeType(platformFile.extension!) 
              : null);
    }
  }
  
  // Simple MIME type detection based on extension
  static String _getMimeType(String extension) {
    final ext = extension.toLowerCase().replaceAll('.', '');
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'svg':
        return 'image/svg+xml';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'csv':
        return 'text/csv';
      case 'txt':
        return 'text/plain';
      case 'html':
      case 'htm':
        return 'text/html';
      case 'json':
        return 'application/json';
      case 'xml':
        return 'application/xml';
      case 'zip':
        return 'application/zip';
      case 'mp3':
        return 'audio/mpeg';
      case 'mp4':
        return 'video/mp4';
      case 'wav':
        return 'audio/wav';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      default:
        return 'application/octet-stream'; // Default binary MIME type
    }
  }
}