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
  double _progress = 0;
  Duration _estimate = Duration();
  XFile? _file;
  TusClient? _client;
  Uri? _fileUrl;
  bool _isLoading = false;
  bool _isSettingsOpen = false;

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
        title: Text('TUS Client Upload Demo'),
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
            subtitle:
                Text('Required for some platforms, but uses more memory'),
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
          ..._buildKeyValueList(_headers, _headerKeyControllers,
              _headerValueControllers, (newHeaders) {
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
          ..._buildKeyValueList(_metadata, _metadataKeyControllers,
              _metadataValueControllers, (newMetadata) {
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
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(height: 12),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Text(
              "This demo uses TUS client to upload a file",
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
                    _progress = 0;
                    _fileUrl = null;
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
                            // Create a storage implementation based on platform
                            final store = await _createStore();

                            // Create a client
                            print("Create a client");
                            _client = TusClient(
                              _file!,
                              store: store,
                              maxChunkSize: 512 * 1024 * 10,
                            );

                            print("Starting upload");
                            
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
                            
                            await _client!.upload(
                              onStart:
                                  (TusClient client, Duration? estimation) {
                                print(estimation);
                              },
                              onComplete: () async {
                                print("Completed!");
                                if (!kIsWeb) {
                                  final tempDir =
                                      await getTemporaryDirectory();
                                  final tempDirectory = Directory(
                                      '${tempDir.path}/${_file?.name}_uploads');
                                  if (tempDirectory.existsSync()) {
                                    tempDirectory.deleteSync(recursive: true);
                                  }
                                }
                                setState(() => _fileUrl = _client!.uploadUrl);
                              },
                              onProgress: (progress, estimate) {
                                print("Progress: $progress");
                                print('Estimate: $estimate');
                                setState(() {
                                  _progress = progress;
                                  _estimate = estimate;
                                });
                              },
                              uri: Uri.parse(_endpointController.text),
                              metadata: metadataMap,
                              headers: headersMap,
                              measureUploadSpeed: !kIsWeb,
                            );
                          },
                    child: Text("Upload"),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _progress == 0 || _client == null
                        ? null
                        : () async {
                            await _client!.pauseUpload();
                          },
                    child: Text("Pause"),
                  ),
                ),
              ],
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
                widthFactor: _progress / 100,
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
                    "Progress: ${_progress.toStringAsFixed(1)}%, estimated time: ${_printDuration(_estimate)}"),
              ),
            ],
          ),
          if (_progress > 0)
            ElevatedButton(
              onPressed: _client == null ? null : () async {
                final result = await _client!.cancelUpload();

                if (result) {
                  setState(() {
                    _progress = 0;
                    _estimate = Duration();
                  });
                }
              },
              child: Text("Cancel"),
            ),
          GestureDetector(
            onTap: _progress != 100
                ? null
                : () async {
                    if (_fileUrl != null) {
                      await launchUrl(_fileUrl!);
                    }
                  },
            child: Container(
              color: _progress == 100 ? Colors.green : Colors.grey,
              padding: const EdgeInsets.all(8.0),
              margin: const EdgeInsets.all(8.0),
              child: Text(
                  _progress == 100 ? "Link to view:\n $_fileUrl" : "-"),
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
      final tempDirectory = Directory('${tempDir.path}/${_file?.name}_uploads');
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

      print("Opening file picker...");
      print("Settings: withData: $_withData, withReadStream: $_withReadStream");
      
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
      if (kIsWeb) {
        print("Running on Web platform, creating StreamXFileWeb");
        final xFile = XFileFactory.fromPlatformFile(platformFile);
        final length = await xFile.length();
        print("Created XFile: ${xFile.name}, length: $length");
        return xFile;
      } else {
        print("Running on native platform");
        if (platformFile.path != null) {
          print("Using file path: ${platformFile.path}");
          final xFile = XFile(platformFile.path!);
          final length = await xFile.length();
          print("Created XFile: ${xFile.name}, length: $length");

          return xFile;
        } else {
          print("File path is null, trying to use bytes");
          if (platformFile.bytes != null) {
            final xFile = XFile.fromData(
              platformFile.bytes!,
              name: platformFile.name,
            );
            final length = await xFile.length();
            print("Created XFile from bytes: ${xFile.name}, length: $length");
            return xFile;
          } else {
            print("No path or bytes available for the file");
            return null;
          }
        }
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
    super.dispose();
  }
}
