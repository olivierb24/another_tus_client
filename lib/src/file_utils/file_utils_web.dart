import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:web/web.dart' as web;
import 'file_utils_interface.dart';

/// Selects files using the browser's native file picker without loading file contents.
Future<List<web.File>> selectWebFiles({
  bool allowMultiple = false,
  List<String> acceptedFileTypes = const [],
}) {
  final completer = Completer<List<web.File>>();

  if (kTesting) print('[selectWebFiles] Creating file input element');

  // Create a temporary file input element
  final input = web.document.createElement('input') as web.HTMLInputElement;
  input.type = 'file';

  // Configure input element
  if (allowMultiple) {
    input.multiple = true;
    if (kTesting) print('[selectWebFiles] Multiple selection enabled');
  }

  // Handle accepted file types
  if (acceptedFileTypes.isNotEmpty) {
    // Special case: if the only item is '*', don't set any accept filter (accept all)
    if (acceptedFileTypes.length == 1 && acceptedFileTypes[0] == '*') {
      if (kTesting) print('[selectWebFiles] Accept all file types (*)');
    } else {
      input.accept = acceptedFileTypes.join(',');
      if (kTesting)
        print('[selectWebFiles] Accept types: ${acceptedFileTypes.join(',')}');
    }
  }

  // Hide the input element
  input.style.display = 'none';

  // Add the input to the document body
  web.document.body?.appendChild(input);
  if (kTesting) print('[selectWebFiles] Input added to document body');

  // Handle file selection
  input.addEventListener(
    'change',
    (web.Event event) {
      if (kTesting) print('[selectWebFiles] Change event fired');

      final selectedFiles = <web.File>[];

      if (input.files != null) {
        final files = input.files!;
        if (kTesting) print('[selectWebFiles] ${files.length} files selected');

        // Convert FileList to List<File>
        for (var i = 0; i < files.length; i++) {
          final file = files.item(i);
          if (file != null) {
            if (kTesting) {
              print(
                  '[selectWebFiles] File: ${file.name}, size: ${file.size} bytes');
            }
            selectedFiles.add(file);
          }
        }
      }

      // Clean up
      web.document.body?.removeChild(input);
      if (kTesting) print('[selectWebFiles] Input removed from document');

      // Return the selected files
      completer.complete(selectedFiles);
    }.toJS,
  );

  // Open the file picker dialog
  if (kTesting) print('[selectWebFiles] Opening file picker dialog');
  input.click();

  // Set a safety timeout (2 minutes)
  Timer(Duration(minutes: 2), () {
    if (!completer.isCompleted) {
      if (kTesting)
        print('[selectWebFiles] Timeout reached, assuming no files selected');
      try {
        web.document.body?.removeChild(input);
      } catch (_) {
        // Element might have been removed already
      }
      completer.complete([]);
    }
  });

  return completer.future;
}

/// XFile implementation that supports efficient streaming from web.File objects.
class NativeWebXFile extends XFile {
  final web.File _file;
  final String? _mimeType;

  NativeWebXFile(web.File file, {String? mimeType})
      : _file = file,
        _mimeType = mimeType ?? file.type,
        super(
          '', 
          name: file.name,
          length: file.size,
          mimeType: mimeType ?? file.type,
          bytes: null,
          lastModified: file.lastModified != 0 
              ? DateTime.fromMillisecondsSinceEpoch(file.lastModified) 
              : null,
        ) {
    if (kTesting) {
      print('[NativeWebXFile] Constructor called with web.File:');
      print('  name: ${_file.name}');
      print('  size: ${_file.size} bytes');
      print('  type: ${_file.type}');
    }
  }

  @override
  Stream<Uint8List> openRead([int? start, int? end]) {
    if (kTesting)
      print('[NativeWebXFile] openRead called with start: $start, end: $end');

    // Calculate range. We treat the provided 'end' as exclusive.
    final int fileSize = _file.size;
    final int from = start ?? 0;
    final int to = (end != null && end < fileSize) ? end - 1 : fileSize - 1;

    if (kTesting) {
      print(
          '[NativeWebXFile] Calculated range: from $from to $to (fileSize: $fileSize)');
    }

    if (from > to) {
      if (kTesting)
        print('[NativeWebXFile] from > to, returning empty stream.');
      return const Stream<Uint8List>.empty();
    }

    // Use Blob slicing API directly on the File object (File extends Blob)
    return _createBlobSliceStream(from, to + 1);
  }

  Stream<Uint8List> _createBlobSliceStream(int start, int end) async* {
    if (kTesting)
      print('[NativeWebXFile] _createBlobSliceStream called with start: $start, end: $end');

    // Slice the File object directly: slice(start, end) returns a new Blob
    final slicedBlob = _file.slice(start, end);
    if (kTesting) print('[NativeWebXFile] File sliced from $start to $end');

    // Read the sliced blob as an ArrayBuffer
    final arrayBuffer = await slicedBlob.arrayBuffer().toDart as ByteBuffer;
    final bytes = Uint8List.view(arrayBuffer);
    if (kTesting)
      print('[NativeWebXFile] Yielding sliced bytes of length: ${bytes.length}');
    yield bytes;
  }

  @override
  Future<int> length() async {
    if (kTesting)
      print('[NativeWebXFile] length() called. Returning file size: ${_file.size}');
    return _file.size;
  }
}

/// Creates an XFile from a native web.File object.
XFile createXFileFromWebFile(web.File file, {String? mimeType}) {
  if (kTesting)
    print('[createXFileFromWebFile] Creating XFile from: ${file.name}');
  return NativeWebXFile(file, mimeType: mimeType);
}

/// Picks files using the browser's file selector and converts them to XFiles.
Future<List<XFile>?> pickWebFilesForUpload({
  bool allowMultiple = false,
  List<String> acceptedFileTypes = const [],
}) async {
  if (kTesting) print('[pickFilesForUpload] Starting file selection process');

  final webFiles = await selectWebFiles(
    allowMultiple: allowMultiple,
    acceptedFileTypes: acceptedFileTypes,
  );

  if (webFiles.isEmpty) {
    if (kTesting)
      print('[pickWebFilesForUpload] No files selected, returning null');
    return null;
  }
  
  if (kTesting)
    print('[pickFilesForUpload] Converting ${webFiles.length} files to XFiles');
  final xfiles = webFiles.map((file) => createXFileFromWebFile(file)).toList();

  if (kTesting) print('[pickFilesForUpload] Returning ${xfiles.length} XFiles');

  return xfiles;
}