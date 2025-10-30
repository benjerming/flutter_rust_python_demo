import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:integrate_python_demo/python/asset_manager.dart';
import 'package:integrate_python_demo/src/rust/api/executor.dart';
import 'package:path/path.dart' as p;

class PythonHandler {
  PythonHandler._internal();

  static final PythonHandler instance = PythonHandler._internal();

  final PythonAssetManager _assetManager = PythonAssetManager.instance;

  bool get isInitialized => !Platform.isAndroid || _assetManager.isInitialized;

  Future<void> ensureInitialized() async {
    if (Platform.isAndroid) {
      await _assetManager.ensureInitialized();
    }
  }

  Future<(String stdout, String stderr)> runCode(String code) async {
    await ensureInitialized();

    String exec;
    String? pythonLibraryDir;
    List<String>? pythonPaths;

    if (Platform.isAndroid) {
      final String pythonAbiDir = (await _assetManager.getPythonAbiDir()).path;
      final String pythonStdlibDir =
          (await _assetManager.getPythonStdlibDir()).path;
      exec = p.join(pythonAbiDir, 'python3.11');
      pythonLibraryDir = pythonAbiDir;
      pythonPaths = [pythonAbiDir, pythonStdlibDir];
      debugPrint('[PythonEnv] exec=$exec');
    } else {
      exec = 'python';
    }

    return executePythonScript(
      exec: exec,
      code: code,
      pythonLibraryDir: pythonLibraryDir,
      pythonPaths: pythonPaths,
    );
  }
}
