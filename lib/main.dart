// The original content is temporarily commented out to allow generating a self-contained demo - feel free to uncomment later.

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:integrate_python_demo/src/rust/api/executor.dart';
import 'package:integrate_python_demo/src/rust/api/os.dart';
import 'package:integrate_python_demo/src/rust/frb_generated.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Integrate Python Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const MyHomePage(title: 'Integrate Python Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool _isExtracting = false;
  String _stdout = '';
  String _stderr = '';
  String _exception = '';

  @override
  void initState() {
    super.initState();
    _kickOffAssetExtraction();
  }

  Future<void> _kickOffAssetExtraction() async {
    // Do not run on web since file system APIs are not supported.
    if (kIsWeb) return;
    if (mounted) {
      setState(() {
        _isExtracting = true;
      });
    }
    try {
      await _ensureNativeDemoInstalledFromZip();
      await _ensurePythonInstalledFromZip();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('解压失败: $e'), duration: Duration(seconds: 5)),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExtracting = false;
        });
      }
    }
  }

  Future<Directory> _getAppSupportDir() async {
    return await getApplicationSupportDirectory();
  }

  Future<Directory> _getPythonDir() async {
    final Directory supportDir = await _getAppSupportDir();
    return Directory(p.join(supportDir.path, 'python-3.11'));
  }

  Future<Directory> _getPythonAbiDir() async {
    final Directory pythonDir = await _getPythonDir();
    // detect current cpu is armeabi-v7a or arm64-v8a
    final String cpu = abi();
    debugPrint('cpu=$cpu');
    return Directory(p.join(pythonDir.path, 'python-$cpu'));
  }

  Future<Directory> _getPythonStdlibDir() async {
    final Directory pythonDir = await _getPythonDir();
    return Directory(p.join(pythonDir.path, 'python-stdlib'));
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
    // 解压assets/nativeexe和assets/libnativelib.so到程序私有目录
    await _extractAssetFile(
      'assets/${abi()}/nativeexe',
      (await _getAppSupportDir()).path,
    );
    await _extractAssetFile(
      'assets/${abi()}/libnativelib.so',
      (await _getAppSupportDir()).path,
    );
  }

  Future<void> _ensurePythonInstalledFromZip() async {
    final Directory supportDir = await _getAppSupportDir();
    final String pythonDirPath = p.join(supportDir.path, 'python-3.11');
    debugPrint('[PY] supportDir=${supportDir.path}');
    debugPrint('[PY] targetDir=$pythonDirPath');

    // 读取 assets 压缩包
    const String zipAssetPath = 'assets/python-3.11.zip';
    List<int> zipBytes;
    try {
      final ByteData zipData = await rootBundle.load(zipAssetPath);
      zipBytes = zipData.buffer.asUint8List(
        zipData.offsetInBytes,
        zipData.lengthInBytes,
      );
      debugPrint('[PY] asset loaded: $zipAssetPath, size=${zipBytes.length}');
    } catch (e) {
      debugPrint('[PY][ERR] load asset failed: $zipAssetPath, error=$e');
      rethrow;
    }

    // 清理旧目录
    final Directory pythonDir = Directory(pythonDirPath);
    if (await pythonDir.exists()) {
      try {
        await pythonDir.delete(recursive: true);
        debugPrint('[PY] old dir removed');
      } catch (e) {
        // 如果删除失败，尝试重命名避免占用
        final String backupPath = p.join(
          supportDir.path,
          'python-3.11.bak_${DateTime.now().millisecondsSinceEpoch}',
        );
        try {
          await pythonDir.rename(backupPath);
          debugPrint('[PY] old dir renamed to $backupPath');
        } catch (_) {}
      }
    }
    await pythonDir.create(recursive: true);

    // 解压
    int filesWritten = 0;
    try {
      final Archive archive = ZipDecoder().decodeBytes(zipBytes, verify: false);
      debugPrint('[PY] archive entries=${archive.length}');
      for (final ArchiveFile file in archive) {
        // 路径规范化与安全检查
        final String normalizedName = p.normalize(
          file.name.replaceAll('\\', '/'),
        );
        if (normalizedName.contains('..') || p.isAbsolute(normalizedName)) {
          debugPrint('[PY][WARN] skip suspicious entry: ${file.name}');
          continue;
        }
        final String outPath = p.normalize(
          p.join(pythonDirPath, normalizedName),
        );
        if (!p.isWithin(pythonDirPath, outPath)) {
          debugPrint('[PY][WARN] skip outside path: $outPath');
          continue;
        }

        if (file.isFile) {
          final File outFile = File(outPath);
          await outFile.parent.create(recursive: true);
          final List<int> content = (file.content is List<int>)
              ? (file.content as List<int>)
              : (file.content as Uint8List).toList();
          await outFile.writeAsBytes(content, flush: true);
          filesWritten++;
        } else {
          await Directory(outPath).create(recursive: true);
        }
      }
    } catch (e) {
      debugPrint('[PY][ERR] unzip failed: $e');
      rethrow;
    }

    debugPrint('[PY] extract done, files=$filesWritten, stamp written');
  }

  void _executeNativeDemo() async {
    debugPrint('executeNativeDemo start');
    try {
      final String dir = (await _getNativeDemoDir()).path;
      final String exe = p.join(dir, 'nativeexe');
      final ldLibraryPath = dir;
      final (String stdout, String stderr) = await executeCommand(
        exec: exe,
        args: [],
        ldLibraryPath: [ldLibraryPath],
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
      String exec;
      String? pythonLibraryDir;
      List<String>? pythonPaths;
      if (Platform.isAndroid) {
        // use integrated python
        final pythonAbiDir = (await _getPythonAbiDir()).path;
        final pythonStdlibDir = (await _getPythonStdlibDir()).path;
        exec = p.join(pythonAbiDir, 'python3.11');
        pythonLibraryDir = pythonAbiDir;
        debugPrint('exec=$exec, exists=${await File(exec).exists()}');
        pythonPaths = [pythonAbiDir, pythonStdlibDir];
      } else {
        // use system python
        exec = "python";
      }
      final String code = "import sys;print(sys.version)";
      final (String stdout, String stderr) = await executePythonScript(
        exec: exec,
        code: code,
        pythonLibraryDir: pythonLibraryDir,
        pythonPaths: pythonPaths,
      );
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
          body: Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text("stdout=", style: TextStyle(color: Colors.cyan)),
                Text(_stdout),
                const Text("stderr=", style: TextStyle(color: Colors.red)),
                Text(_stderr),
                const Text("exception=", style: TextStyle(color: Colors.red)),
                Text(_exception),
              ],
            ),
          ),
          floatingActionButton: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (Platform.isAndroid) OutlinedButton(
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

// import 'package:flutter/material.dart';
// import 'package:integrate_python_demo/src/rust/api/simple.dart';
// import 'package:integrate_python_demo/src/rust/frb_generated.dart';

// Future<void> main() async {
//   await RustLib.init();
//   runApp(const MyApp());
// }

// class MyApp extends StatelessWidget {
//   const MyApp({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       home: Scaffold(
//         appBar: AppBar(title: const Text('flutter_rust_bridge quickstart')),
//         body: Center(
//           child: Text(
//             'Action: Call Rust `greet("Tom")`\nResult: `${greet(name: "Tom")}`',
//           ),
//         ),
//       ),
//     );
//   }
// }
