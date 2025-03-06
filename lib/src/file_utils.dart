import 'dart:async';
import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';

/// XFile implementation that supports proper streaming on web
class StreamXFileWeb extends XFile {
  final PlatformFile _platformFile;
  
  StreamXFileWeb(this._platformFile, {String? mimeType})
      : super(
          '', // Empty path as it's not applicable on web
          name: _platformFile.name,
          length: _platformFile.size, // Use known size from PlatformFile
          mimeType: mimeType,
        );

  @override
  Stream<Uint8List> openRead([int? start, int? end]) {
    // Handle both streaming and in-memory approaches
    final Stream<List<int>>? baseStream = _platformFile.readStream;
    final Uint8List? bytes = _platformFile.bytes;
    
    // Calculate range
    final int fileSize = _platformFile.size;
    final int from = start ?? 0;
    final int to = (end != null && end < fileSize) ? end : fileSize - 1;
    
    if (from > to) {
      return const Stream<Uint8List>.empty();
    }
    
    // CASE 1: We have bytes available (if withData: true was used)
    if (bytes != null) {
      // Return requested range from the byte array
      final chunk = bytes.sublist(
        from.clamp(0, bytes.length), 
        (to + 1).clamp(0, bytes.length)
      );
      return Stream.value(chunk);
    }
    
    // CASE 2: We have a stream available (if withReadStream: true was used)
    if (baseStream != null) {
      // If no range specified, simply convert the stream to emit Uint8List
      if ((start == null || start == 0) && end == null) {
        return baseStream.map((chunk) {
          if (chunk is Uint8List) return chunk;
          return Uint8List.fromList(chunk);
        });
      }
      
      // Create a controller to emit only the requested byte range
      final controller = StreamController<Uint8List>();
      late StreamSubscription<List<int>> sub;
      
      int bytesToSkip = from;
      int bytesToSend = to - from + 1;
      
      sub = baseStream.listen(
        (chunk) {
          Uint8List uChunk = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
          
          // Skip bytes if needed
          if (bytesToSkip > 0) {
            if (uChunk.length <= bytesToSkip) {
              bytesToSkip -= uChunk.length;
              return; // Skip entire chunk
            } else {
              uChunk = uChunk.sublist(bytesToSkip);
              bytesToSkip = 0;
            }
          }
          
          // Handle end offset
          if (end != null) {
            if (uChunk.length > bytesToSend) {
              controller.add(uChunk.sublist(0, bytesToSend));
              bytesToSend = 0;
              controller.close();
              sub.cancel();
            } else {
              controller.add(uChunk);
              bytesToSend -= uChunk.length;
              if (bytesToSend <= 0) {
                controller.close();
                sub.cancel();
              }
            }
          } else {
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
      
      controller.onCancel = () {
        sub.cancel();
      };
      
      return controller.stream;
    }
    
    // CASE 3: No data source available
    throw UnsupportedError(
      'Unable to read file: No data available (both bytes and readStream are null)'
    );
  }
  
  // Ensure length always returns the known file size
  @override
  Future<int> length() async {
    return _platformFile.size;
  }
}

/// Factory to create XFile instances for web
class XFileFactory {
  /// Creates an XFile from a PlatformFile on web
  static XFile fromPlatformFile(PlatformFile platformFile) {
    String? mimeType;
    if (platformFile.extension != null) {
      mimeType = _getMimeType(platformFile.extension!);
    }
    return StreamXFileWeb(platformFile, mimeType: mimeType);
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