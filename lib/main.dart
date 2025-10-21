import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void main() {
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
      ),
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
  int _counter = 0;
  bool _isExtracting = false;
  
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
      await _ensurePythonInstalledFromZip();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('解压失败: $e')),
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
      zipBytes = zipData.buffer.asUint8List(zipData.offsetInBytes, zipData.lengthInBytes);
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
        final String backupPath = p.join(supportDir.path, 'python-3.11.bak_${DateTime.now().millisecondsSinceEpoch}');
        try { await pythonDir.rename(backupPath); debugPrint('[PY] old dir renamed to $backupPath'); } catch (_) {}
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
        final String normalizedName = p.normalize(file.name.replaceAll('\\', '/'));
        if (normalizedName.contains('..') || p.isAbsolute(normalizedName)) {
          debugPrint('[PY][WARN] skip suspicious entry: ${file.name}');
          continue;
        }
        final String outPath = p.normalize(p.join(pythonDirPath, normalizedName));
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

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            // TRY THIS: Try changing the color here to a specific color (to
            // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
            // change color while the other colors stay the same.
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            // Here we take the value from the MyHomePage object that was created by
            // the App.build method, and use it to set our appbar title.
            title: Text(widget.title),
          ),
          body: Center(
            // Center is a layout widget. It takes a single child and positions it
            // in the middle of the parent.
            child: Column(
              // Column is also a layout widget. It takes a list of children and
              // arranges them vertically. By default, it sizes itself to fit its
              // children horizontally, and tries to be as tall as its parent.
              //
              // Column has various properties to control how it sizes itself and
              // how it positions its children. Here we use mainAxisAlignment to
              // center the children vertically; the main axis here is the vertical
              // axis because Columns are vertical (the cross axis would be
              // horizontal).
              //
              // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
              // action in the IDE, or press "p" in the console), to see the
              // wireframe for each widget.
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Text('You have pushed the button this many times:'),
                Text(
                  '$_counter',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: _isExtracting ? null : _incrementCounter,
            tooltip: 'Increment',
            child: const Icon(Icons.abc),
          ), // This trailing comma makes auto-formatting nicer for build methods.
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
