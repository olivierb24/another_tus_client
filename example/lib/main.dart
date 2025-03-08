import 'package:another_tus_client/another_tus_client.dart';
import 'package:universal_io/io.dart';
import 'package:cross_file/cross_file.dart' show XFile;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TUS Client Upload Demo',
      theme: ThemeData(
        primarySwatch: Colors.teal,
        useMaterial3: true,
      ),
      // Add this to force LTR for the entire app
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: child!,
        );
      },
      home: UploadPage(),
    );
  }
}

class UploadPage extends StatefulWidget {
  @override
  _UploadPageState createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  // Upload manager instance
  late TusUploadManager _uploadManager;
  
  // Current active upload
  String? _activeUploadId;
  ManagedUpload? _activeUpload;
  
  XFile? _file;
  Uri? _fileUrl;
  bool _isLoading = false;
  bool _isSettingsOpen = false;
  bool _isPaused = false;
  bool _isResumable = false;

  // Endpoint settings
  final TextEditingController _endpointController = TextEditingController();

  // FilePicker settings
  bool _withData = true;
  bool _withReadStream = true;

  // Headers and metadata
  List<MapEntry<String, String>> _headers = [MapEntry('', '')];
  List<MapEntry<String, String>> _metadata = [MapEntry('', '')];

  // Persistent controllers for Headers
  final List<TextEditingController> _headerKeyControllers = [];
  final List<TextEditingController> _headerValueControllers = [];

  // Persistent controllers for Metadata
  final List<TextEditingController> _metadataKeyControllers = [];
  final List<TextEditingController> _metadataValueControllers = [];

  @override
  void initState() {
    super.initState();
    // Initialize controllers with the initial values.
    _initializeHeaderControllers();
    _initializeMetadataControllers();
    _loadSettings();
  }

  // Initialize the upload manager
  Future<void> _initializeUploadManager() async {
    final store = await _createStore();
    
    _uploadManager = TusUploadManager(
      serverUrl: Uri.parse(_endpointController.text),
      store: store,
      maxConcurrentUploads: 3,
      autoStart: false, // We'll start manually
      measureUploadSpeed: !kIsWeb,
      retries: 3,
    );
    
    // Listen for upload events
    _uploadManager.uploadEvents.listen((upload) {
      if (upload.id == _activeUploadId) {
        setState(() {
          _activeUpload = upload;
          _isPaused = upload.status == UploadStatus.paused;
          
          // Get upload URL when completed
          if (upload.status == UploadStatus.completed) {
            _fileUrl = upload.client.uploadUrl;
          }
        });
      }
    });
  }

  void _initializeHeaderControllers() {
    _headerKeyControllers.clear();
    _headerValueControllers.clear();
    for (var entry in _headers) {
      _headerKeyControllers.add(TextEditingController(text: entry.key));
      _headerValueControllers.add(TextEditingController(text: entry.value));
    }
  }

  void _initializeMetadataControllers() {
    _metadataKeyControllers.clear();
    _metadataValueControllers.clear();
    for (var entry in _metadata) {
      _metadataKeyControllers.add(TextEditingController(text: entry.key));
      _metadataValueControllers.add(TextEditingController(text: entry.value));
    }
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();

      setState(() {
        _endpointController.text =
            prefs.getString('endpoint') ?? 'http://localhost:8080/files/';
        _withData = prefs.getBool('withData') ?? true;
        _withReadStream = prefs.getBool('withReadStream') ?? true;

        // Load headers
        final headersJson = prefs.getString('headers');
        if (headersJson != null) {
          final Map<String, dynamic> headersMap = jsonDecode(headersJson);
          _headers = headersMap.entries
              .map((e) => MapEntry(e.key, e.value.toString()))
              .toList();
          if (_headers.isEmpty) _headers = [MapEntry('', '')];
        }

        // Load metadata
        final metadataJson = prefs.getString('metadata');
        if (metadataJson != null) {
          final Map<String, dynamic> metadataMap = jsonDecode(metadataJson);
          _metadata = metadataMap.entries
              .map((e) => MapEntry(e.key, e.value.toString()))
              .toList();
          if (_metadata.isEmpty) _metadata = [MapEntry('', '')];
        }
        // Reinitialize controllers after settings load
        _initializeHeaderControllers();
        _initializeMetadataControllers();
      });
      
      // Initialize the upload manager after loading settings
      await _initializeUploadManager();
    } catch (e) {
      print('Error loading settings: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString('endpoint', _endpointController.text);
      await prefs.setBool('withData', _withData);
      await prefs.setBool('withReadStream', _withReadStream);

      // Save headers (removing empty ones)
      final Map<String, String> headersMap = {};
      for (var entry in _headers) {
        if (entry.key.isNotEmpty && entry.value.isNotEmpty) {
          headersMap[entry.key] = entry.value;
        }
      }
      await prefs.setString('headers', jsonEncode(headersMap));

      // Save metadata (removing empty ones)
      final Map<String, String> metadataMap = {};
      for (var entry in _metadata) {
        if (entry.key.isNotEmpty && entry.value.isNotEmpty) {
          metadataMap[entry.key] = entry.value;
        }
      }
      await prefs.setString('metadata', jsonEncode(metadataMap));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Settings saved')),
      );
      
      // Re-initialize the upload manager with new settings
      await _initializeUploadManager();
    } catch (e) {
      print('Error saving settings: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving settings: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('TUS Upload Manager Demo'),
        actions: [
          IconButton(
            icon: Icon(_isSettingsOpen ? Icons.close : Icons.settings),
            onPressed: () {
              setState(() {
                _isSettingsOpen = !_isSettingsOpen;
              });
            },
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _isSettingsOpen
              ? _buildSettingsPanel()
              : _buildUploadPanel(),
    );
  }

  Widget _buildSettingsPanel() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Upload Settings',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          SizedBox(height: 16),
          // Endpoint settings
          Text('Endpoint URL', style: TextStyle(fontWeight: FontWeight.bold)),
          Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              controller: _endpointController,
              decoration: InputDecoration(
                hintText: 'https://your-tus-server.com/files/',
                border: OutlineInputBorder(),
              ),
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
            ),
          ),
          SizedBox(height: 16),
          // FilePicker settings
          Text('File Picker Settings',
              style: TextStyle(fontWeight: FontWeight.bold)),
          CheckboxListTile(
            title: Text('With Data (load file into memory)'),
            subtitle: Text('Required for some platforms, but uses more memory'),
            value: _withData,
            onChanged: (value) {
              setState(() {
                _withData = value ?? true;
              });
            },
          ),
          CheckboxListTile(
            title: Text('With Read Stream (stream file data)'),
            subtitle: Text('More efficient for large files on web'),
            value: _withReadStream,
            onChanged: (value) {
              setState(() {
                _withReadStream = value ?? true;
              });
            },
          ),
          SizedBox(height: 16),
          // Headers
          Text('Custom Headers', style: TextStyle(fontWeight: FontWeight.bold)),
          ..._buildKeyValueList(
              _headers, _headerKeyControllers, _headerValueControllers,
              (newHeaders) {
            setState(() {
              _headers = newHeaders;
            });
          }),
          SizedBox(height: 8),
          OutlinedButton.icon(
            icon: Icon(Icons.add),
            label: Text('Add Header'),
            onPressed: () {
              setState(() {
                _headers.add(MapEntry('', ''));
                _headerKeyControllers.add(TextEditingController());
                _headerValueControllers.add(TextEditingController());
              });
            },
          ),
          SizedBox(height: 16),
          // Metadata
          Text('Metadata', style: TextStyle(fontWeight: FontWeight.bold)),
          ..._buildKeyValueList(
              _metadata, _metadataKeyControllers, _metadataValueControllers,
              (newMetadata) {
            setState(() {
              _metadata = newMetadata;
            });
          }),
          SizedBox(height: 8),
          OutlinedButton.icon(
            icon: Icon(Icons.add),
            label: Text('Add Metadata'),
            onPressed: () {
              setState(() {
                _metadata.add(MapEntry('', ''));
                _metadataKeyControllers.add(TextEditingController());
                _metadataValueControllers.add(TextEditingController());
              });
            },
          ),
          SizedBox(height: 24),
          // Save button
          ElevatedButton.icon(
            icon: Icon(Icons.save),
            label: Text('Save Settings'),
            onPressed: _saveSettings,
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildKeyValueList(
    List<MapEntry<String, String>> items,
    List<TextEditingController> keyControllers,
    List<TextEditingController> valueControllers,
    Function(List<MapEntry<String, String>>) onUpdate,
  ) {
    return items.asMap().entries.map((entry) {
      final index = entry.key;
      return Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: TextField(
                  controller: keyControllers[index],
                  decoration: InputDecoration(
                    hintText: 'Key',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  onChanged: (value) {
                    items[index] = MapEntry(value, items[index].value);
                    onUpdate(items);
                  },
                ),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: TextField(
                  controller: valueControllers[index],
                  decoration: InputDecoration(
                    hintText: 'Value',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  onChanged: (value) {
                    items[index] = MapEntry(items[index].key, value);
                    onUpdate(items);
                  },
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.delete, color: Colors.red),
              onPressed: () {
                if (items.length > 1) {
                  items.removeAt(index);
                  keyControllers.removeAt(index);
                  valueControllers.removeAt(index);
                  onUpdate(items);
                }
              },
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildUploadPanel() {
    // Get progress and status from active upload if available
    double progress = 0;
    Duration estimate = Duration.zero;
    UploadStatus status = UploadStatus.ready;
    
    if (_activeUpload != null) {
      progress = _activeUpload!.progress;
      estimate = _activeUpload!.estimate;
      status = _activeUpload!.status;
    }
    
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(height: 12),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Text(
              "This demo uses TUS Upload Manager to upload a file",
              style: TextStyle(fontSize: 18),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(6),
            child: Card(
              color: Colors.teal,
              child: InkWell(
                onTap: () async {
                  if (!kIsWeb && !await ensurePermissions()) {
                    return;
                  }

                  _file = await _getXFile();
                  setState(() {
                    _activeUploadId = null;
                    _activeUpload = null;
                    _fileUrl = null;
                    _isResumable = false;
                  });
                },
                child: Container(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    children: <Widget>[
                      Icon(Icons.cloud_upload, color: Colors.white, size: 60),
                      Text(
                        "Upload a file",
                        style: TextStyle(fontSize: 25, color: Colors.white),
                      ),
                      if (_file != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            "Selected: ${_file!.name}",
                            style: TextStyle(fontSize: 14, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: ElevatedButton(
                    onPressed: _file == null
                        ? null
                        : () async {
                            setState(() {
                              _isPaused = false;
                              _isResumable = false;
                            });

                            print("Adding file to upload manager");

                            // Convert header entries to map
                            final headersMap = <String, String>{};
                            for (var entry in _headers) {
                              if (entry.key.isNotEmpty) {
                                headersMap[entry.key] = entry.value;
                              }
                            }

                            // Convert metadata entries to map
                            final metadataMap = <String, String>{};
                            for (var entry in _metadata) {
                              if (entry.key.isNotEmpty) {
                                metadataMap[entry.key] = entry.value;
                              }
                            }

                            final timestamp = DateTime.now().millisecondsSinceEpoch;
                            final uniqueFileName = '${timestamp}_${_file?.name ?? 'file'}';

                            metadataMap["contentType"] = _file?.mimeType ??
                                'application/octet-stream';
                            metadataMap["objectName"] = uniqueFileName;

                            // Add the upload to the manager
                            _activeUploadId = await _uploadManager.addUpload(
                              _file!,
                              metadata: metadataMap,
                              headers: headersMap,
                            );
                            
                            // Get the upload object
                            _activeUpload = _uploadManager.getUpload(_activeUploadId!);
                            
                            setState(() {});
                            
                            // Start the upload
                            await _uploadManager.startUpload(_activeUploadId!);
                          },
                    child: Text("Upload"),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _activeUploadId == null
                        ? null
                        : () async {
                            if (status == UploadStatus.uploading) {
                              print("Pausing upload...");
                              await _uploadManager.pauseUpload(_activeUploadId!);
                            } else if (status == UploadStatus.paused) {
                              print("Resuming upload...");
                              await _uploadManager.resumeUpload(_activeUploadId!);
                            }
                          },
                    child: Text(status == UploadStatus.paused ? "Resume" : "Pause"),
                  ),
                ),
              ],
            ),
          ),
          // Check Resumable button - only show when paused
          if (status == UploadStatus.paused)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ElevatedButton(
                onPressed: _activeUploadId == null
                    ? null
                    : () async {
                        // Check if the upload is resumable
                        final upload = _uploadManager.getUpload(_activeUploadId!);
                        if (upload != null) {
                          // Use the underlying TusClient to check resumability
                          final isResumable = await upload.client.isResumable();
                          setState(() {
                            _isResumable = isResumable;
                          });
                          
                          // Show the result
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(isResumable
                                  ? 'Upload is resumable!'
                                  : 'Upload is NOT resumable.'),
                              backgroundColor: isResumable ? Colors.green : Colors.red,
                            ),
                          );
                        }
                      },
                child: Text("Check if Resumable"),
              ),
            ),
          Stack(
            children: <Widget>[
              Container(
                margin: const EdgeInsets.all(8),
                padding: const EdgeInsets.all(1),
                color: Colors.grey,
                width: double.infinity,
                child: Text(" "),
              ),
              FractionallySizedBox(
                widthFactor: progress / 100,
                child: Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.all(1),
                  color: Colors.green,
                  child: Text(" "),
                ),
              ),
              Container(
                margin: const EdgeInsets.all(8),
                padding: const EdgeInsets.all(1),
                width: double.infinity,
                child: Text(
                    "Progress: ${progress.toStringAsFixed(1)}%, estimated time: ${_printDuration(estimate)}"),
              ),
            ],
          ),
          if (_activeUploadId != null)
            ElevatedButton(
              onPressed: () async {
                final result = await _uploadManager.cancelUpload(_activeUploadId!);
                if (result) {
                  setState(() {
                    _activeUploadId = null;
                    _activeUpload = null;
                    _fileUrl = null;
                    _isResumable = false;
                  });
                }
              },
              child: Text("Cancel"),
            ),
          // Status indicator
          if (_activeUploadId != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Card(
                color: _getStatusColor(status),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    "Status: ${status.toString().split('.').last}",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          // Resumable status indicator
          if (_isPaused)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Card(
                color: _isResumable ? Colors.green.shade800 : Colors.grey,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    _isResumable 
                      ? "Upload is resumable" 
                      : "Resumability status unknown - Check above",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          // File URL when complete
          if (status == UploadStatus.completed && _fileUrl != null)
            GestureDetector(
              onTap: () async {
                if (_fileUrl != null) {
                  await launchUrl(_fileUrl!);
                }
              },
              child: Container(
                color: Colors.green,
                padding: const EdgeInsets.all(8.0),
                margin: const EdgeInsets.all(8.0),
                child: Text("Link to view:\n $_fileUrl"),
              ),
            ),
          // Display current settings summary
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Current Settings:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('Endpoint: ${_endpointController.text}'),
                    Text(
                        'File picker: withData: $_withData, withReadStream: $_withReadStream'),
                    Text(
                        'Headers: ${_headers.where((e) => e.key.isNotEmpty).length} defined'),
                    Text(
                        'Metadata: ${_metadata.where((e) => e.key.isNotEmpty).length} defined'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper to get color based on upload status
  Color _getStatusColor(UploadStatus status) {
    switch (status) {
      case UploadStatus.ready:
        return Colors.blue;
      case UploadStatus.uploading:
        return Colors.orange;
      case UploadStatus.paused:
        return Colors.purple;
      case UploadStatus.completed:
        return Colors.green;
      case UploadStatus.failed:
        return Colors.red;
      case UploadStatus.cancelled:
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }

  String _printDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    final twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return '$twoDigitMinutes:$twoDigitSeconds';
  }

  /// Create a platform-appropriate store
  Future<TusStore> _createStore() async {
    if (kIsWeb) {
      // Use IndexedDB for web
      return TusIndexedDBStore();
    } else {
      // Use file system for mobile/desktop
      final tempDir = await getTemporaryDirectory();
      final tempDirectory = Directory('${tempDir.path}/tus_uploads');
      if (!tempDirectory.existsSync()) {
        tempDirectory.createSync(recursive: true);
      }
      return TusFileStore(tempDirectory);
    }
  }

  /// Get a file for upload using file picker
  Future<XFile?> _getXFile() async {
    try {
      print("Starting file selection...");

      if (!kIsWeb && !await ensurePermissions()) {
        print("Permissions not granted");
        return null;
      }

      if (kIsWeb) {
        print("Running on Web platform, using custom picker");
        final result = await pickWebFilesForUpload(
          allowMultiple: false,
          acceptedFileTypes: ['*'], // Accept all
        );

        if (result == null) {
          print("No file selected");
          return null;
        }

        final size = await result.first.length();

        print("File selected: ${result.first.name}");
        print("File size: ${size} bytes");
        print("File path: ${result.first.path}");

        return result.first;
      } else {
        print("Running on native platform, using file_picker");
        print("Opening file picker...");
        print(
            "Settings: withData: $_withData, withReadStream: $_withReadStream");

        final result = await FilePicker.platform.pickFiles(
          withData: _withData,
          withReadStream: _withReadStream,
        );

        if (result == null) {
          print("No file selected");
          return null;
        }

        print("File selected: ${result.files.first.name}");
        print("File size: ${result.files.first.size} bytes");
        print("File path: ${result.files.first.path}");
        print("Has file data: ${result.files.first.bytes != null}");
        print("Has read stream: ${result.files.first.readStream != null}");

        final platformFile = result.files.first;

        print("Creating XFile from PlatformFile...");
        return platformFile.xFile;
      }
    } catch (e, stackTrace) {
      print("Error selecting file: $e");
      print("Stack trace: $stackTrace");
      return null;
    }
  }

  Future<bool> ensurePermissions() async {
    var enableStorage = true;

    if (Platform.isAndroid) {
      final devicePlugin = DeviceInfoPlugin();
      final androidDeviceInfo = await devicePlugin.androidInfo;
      _androidSdkVersion = androidDeviceInfo.version.sdkInt;
      enableStorage = _androidSdkVersion < 33;
    }

    final storage = enableStorage
        ? await Permission.storage.status
        : PermissionStatus.granted;
    final photos = Platform.isIOS
        ? await Permission.photos.status
        : PermissionStatus.granted;

    if (!storage.isGranted) {
      await Permission.storage.request();
    }

    if (Platform.isIOS && !photos.isGranted) {
      await Permission.photos.request();
    }

    return (enableStorage ? storage.isGranted : true) &&
        (Platform.isIOS ? photos.isGranted : true);
  }

  int _androidSdkVersion = 0;

  @override
  void dispose() {
    _endpointController.dispose();
    // Dispose header controllers
    for (var controller in _headerKeyControllers) {
      controller.dispose();
    }
    for (var controller in _headerValueControllers) {
      controller.dispose();
    }
    // Dispose metadata controllers
    for (var controller in _metadataKeyControllers) {
      controller.dispose();
    }
    for (var controller in _metadataValueControllers) {
      controller.dispose();
    }
    // Dispose upload manager
    _uploadManager.dispose();
    super.dispose();
  }
}