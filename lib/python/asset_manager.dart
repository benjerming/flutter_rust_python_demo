import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:integrate_python_demo/src/rust/api/os.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PythonAssetManager {
  PythonAssetManager._internal();

  static final PythonAssetManager instance = PythonAssetManager._internal();

  static const String _pythonDirName = 'python-3.11';
  static const String _zipAssetPath = 'assets/python-3.11.zip';
  static const String _stampFileName = '.asset_signature';

  Future<void>? _initializing;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  Future<void> ensureInitialized() {
    if (!Platform.isAndroid) {
      _isInitialized = true;
      return Future.value();
    }
    if (_isInitialized) {
      return Future.value();
    }
    return _initializing ??= _initialize();
  }

  Future<Directory> getPythonDir() async {
    await ensureInitialized();
    final Directory supportDir = await _getAppSupportDir();
    return Directory(p.join(supportDir.path, _pythonDirName));
  }

  Future<Directory> getPythonAbiDir() async {
    await ensureInitialized();
    final Directory pythonDir = await getPythonDir();
    final String cpu = abi();
    return Directory(p.join(pythonDir.path, 'python-$cpu'));
  }

  Future<Directory> getPythonStdlibDir() async {
    await ensureInitialized();
    final Directory pythonDir = await getPythonDir();
    return Directory(p.join(pythonDir.path, 'python-stdlib'));
  }

  Future<void> _initialize() async {
    try {
      debugPrint('[PythonAssetManager] initialize start');
      final Directory supportDir = await _getAppSupportDir();
      final Directory pythonDir = Directory(
        p.join(supportDir.path, _pythonDirName),
      );
      final File stampFile = File(p.join(pythonDir.path, _stampFileName));

      final ByteData zipData = await rootBundle.load(_zipAssetPath);
      final Uint8List zipBytes = zipData.buffer.asUint8List(
        zipData.offsetInBytes,
        zipData.lengthInBytes,
      );
      final String assetSignature = _computeAssetSignature(zipBytes);

      if (await pythonDir.exists() && await stampFile.exists()) {
        try {
          final String existingSignature = await stampFile.readAsString();
          if (existingSignature == assetSignature) {
            debugPrint(
              '[PythonAssetManager] python assets already extracted, ignore..',
            );
            _isInitialized = true;
            return;
          }
        } catch (e) {
          debugPrint('[PythonAssetManager][WARN] read stamp failed: $e');
        }
      }

      await _preparePythonDir(pythonDir, supportDir);
      await _extractZipToDir(zipBytes, pythonDir.path);

      await stampFile.parent.create(recursive: true);
      await stampFile.writeAsString(assetSignature, flush: true);

      _isInitialized = true;
      debugPrint('[PythonAssetManager] extraction successfully finished');
    } finally {
      _initializing = null;
    }
  }

  Future<void> _preparePythonDir(
    Directory pythonDir,
    Directory supportDir,
  ) async {
    if (!await pythonDir.exists()) {
      await pythonDir.create(recursive: true);
      return;
    }

    try {
      await pythonDir.delete(recursive: true);
      await pythonDir.create(recursive: true);
    } catch (e) {
      debugPrint('[PythonAssetManager][WARN] delete dir failed: $e');
      final String backupPath = p.join(
        supportDir.path,
        '$_pythonDirName.bak_${DateTime.now().millisecondsSinceEpoch}',
      );
      try {
        await pythonDir.rename(backupPath);
        await pythonDir.create(recursive: true);
        debugPrint('[PythonAssetManager] existing dir renamed to $backupPath');
      } catch (renameErr) {
        debugPrint('[PythonAssetManager][ERR] rename dir failed: $renameErr');
        rethrow;
      }
    }
  }

  Future<void> _extractZipToDir(
    List<int> zipBytes,
    String targetDirPath,
  ) async {
    int filesWritten = 0;
    try {
      final Archive archive = ZipDecoder().decodeBytes(zipBytes, verify: false);
      debugPrint('[PythonAssetManager] archive entries=${archive.length}');
      for (final ArchiveFile file in archive) {
        final String normalizedName = p.normalize(
          file.name.replaceAll('\\', '/'),
        );
        if (normalizedName.contains('..') || p.isAbsolute(normalizedName)) {
          debugPrint(
            '[PythonAssetManager][WARN] skip suspicious entry: ${file.name}',
          );
          continue;
        }
        final String outPath = p.normalize(
          p.join(targetDirPath, normalizedName),
        );
        if (!p.isWithin(targetDirPath, outPath)) {
          debugPrint('[PythonAssetManager][WARN] skip outside path: $outPath');
          continue;
        }

        if (file.isFile) {
          final File outFile = File(outPath);
          await outFile.parent.create(recursive: true);
          late final List<int> content;
          final Object rawContent = file.content;
          if (rawContent is List<int>) {
            content = rawContent;
          } else if (rawContent is Uint8List) {
            content = rawContent;
          } else {
            content = (rawContent as Uint8List).toList();
          }
          await outFile.writeAsBytes(content, flush: true);
          filesWritten++;
        } else {
          await Directory(outPath).create(recursive: true);
        }
      }
      debugPrint('[PythonAssetManager] extract done, files=$filesWritten');
    } catch (e) {
      debugPrint('[PythonAssetManager][ERR] unzip failed: $e');
      rethrow;
    }
  }

  Future<Directory> _getAppSupportDir() async {
    return getApplicationSupportDirectory();
  }

  String _computeAssetSignature(List<int> bytes) {
    return bytes.length.toString();
  }
}
