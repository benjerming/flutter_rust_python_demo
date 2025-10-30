import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:integrate_python_demo/python/handler.dart';
import 'package:integrate_python_demo/src/rust/api/executor.dart';
import 'package:integrate_python_demo/src/rust/api/os.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PythonPage extends StatefulWidget {
  const PythonPage({super.key, required this.title});

  final String title;

  @override
  State<PythonPage> createState() => _PythonPageState();
}

class _PythonPageState extends State<PythonPage> {
  final PythonHandler _handler = PythonHandler.instance;
  bool _isExtracting = false;
  String _stdout = '';
  String _stderr = '';
  String _exception = '';

  @override
  void initState() {
    super.initState();
    _androidAssetExtraction();
  }

  Future<void> _androidAssetExtraction() async {
    if (!Platform.isAndroid) return;
    final bool showProgress = mounted && !_handler.isInitialized;
    if (showProgress) {
      setState(() {
        _isExtracting = true;
      });
    }
    try {
      await _ensureNativeDemoInstalledFromZip();
      await _handler.ensureInitialized();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('解压失败: $e'), duration: Duration(seconds: 5)),
        );
      }
    } finally {
      if (showProgress && mounted) {
        setState(() {
          _isExtracting = false;
        });
      }
    }
  }

  Future<Directory> _getAppSupportDir() async {
    return await getApplicationSupportDirectory();
  }

  Future<Directory> _getNativeDemoDir() async {
    final Directory supportDir = await _getAppSupportDir();
    return Directory(p.join(supportDir.path, 'assets', abi()));
  }

  Future<void> _extractAssetFile(String assetPath, String targetDir) async {
    final ByteData assetData = await rootBundle.load(assetPath);
    final List<int> assetBytes = assetData.buffer.asUint8List(
      assetData.offsetInBytes,
      assetData.lengthInBytes,
    );
    final File targetFile = File(p.join(targetDir, assetPath));
    await targetFile.parent.create(recursive: true);
    await targetFile.writeAsBytes(assetBytes, flush: true);
  }

  Future<void> _ensureNativeDemoInstalledFromZip() async {
    await _extractAssetFile(
      'assets/${abi()}/nativeexe',
      (await _getAppSupportDir()).path,
    );
    await _extractAssetFile(
      'assets/${abi()}/libnativelib.so',
      (await _getAppSupportDir()).path,
    );
  }

  void _executeNativeDemo() async {
    debugPrint('executeNativeDemo start');
    try {
      final String dir = (await _getNativeDemoDir()).path;
      final String exe = p.join(dir, 'nativeexe');
      final (String stdout, String stderr) = await executeCommand(
        exec: exe,
        args: [],
        env: {'LD_LIBRARY_PATH': dir},
      );
      debugPrint('executeNativeDemo result=$stdout');
      setState(() {
        _stdout = stdout;
        _stderr = stderr;
        _exception = '';
      });
    } catch (e) {
      debugPrint('executeNativeDemo error=$e');
      setState(() {
        _stdout = '';
        _stderr = '';
        _exception = e.toString();
      });
    }
  }

  void _executeScript() async {
    debugPrint('executeScript start');
    try {
      const String code = "import sys;print(sys.version);";
      final (String stdout, String stderr) = await _handler.runCode(code);
      final String pythonVersion = stdout.isEmpty
          ? stderr
          : "stdout=$stdout\nstderr=$stderr";
      debugPrint('executeScript result=$pythonVersion');
      if (mounted) {
        setState(() {
          _stdout = stdout;
          _stderr = stderr;
          _exception = '';
        });
      }
    } catch (e) {
      debugPrint('executeScript error=$e');
      setState(() {
        _stdout = '';
        _stderr = '';
        _exception = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            title: Text(widget.title),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text("stdout=", style: TextStyle(color: Colors.cyan)),
                          Text(_stdout),
                          const Text(
                            "stderr=",
                            style: TextStyle(color: Colors.red),
                          ),
                          Text(_stderr),
                          const Text(
                            "exception=",
                            style: TextStyle(color: Colors.red),
                          ),
                          Text(_exception),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    left: 10,
                    right: 10,
                    bottom: 10,
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(
                              context,
                            ).popUntil((route) => route.isFirst);
                          },
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('返回'),
                        ),
                        const SizedBox(width: 12),
                        if (Platform.isAndroid)
                          OutlinedButton(
                            onPressed: _executeNativeDemo,
                            child: const Text('Native Demo'),
                          ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: _executeScript,
                          child: const Text('Python Version'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_isExtracting) ...[
          const ModalBarrier(dismissible: false, color: Colors.black54),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text(
                  '正在解压 Python，请稍候…',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
