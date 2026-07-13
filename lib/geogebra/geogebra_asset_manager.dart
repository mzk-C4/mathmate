import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Installs the bundled GeoGebra runtime once and shares it across every
/// feature that embeds a GeoGebra canvas.
///
/// A versioned directory keeps an app update from deleting files that are
/// still in use by another WebView. The completion marker is written last, so
/// an interrupted extraction is repaired on the next launch.
class GeogebraAssetManager {
  GeogebraAssetManager._();

  static const String runtimeVersion = '5.4.920.0';
  static const String _assetRoot = 'assets/geogebra';
  static const String _manifestAsset = '$_assetRoot/file_manifest.txt';
  static const String _completionMarker = '.runtime-ready';

  static Future<String>? _installation;

  static Future<String> ensureInstalled() {
    return _installation ??= _install()
        .whenComplete(() {
          // Keep successful installations cached for this process. A failed
          // install may be retried by the user without restarting the app.
        })
        .catchError((Object error, StackTrace stackTrace) {
          _installation = null;
          Error.throwWithStackTrace(error, stackTrace);
        });
  }

  static Future<String> htmlPath(String fileName) async {
    final String root = await ensureInstalled();
    final File file = File('$root/$fileName');
    if (!await file.exists()) {
      _installation = null;
      final String repairedRoot = await ensureInstalled();
      final File repairedFile = File('$repairedRoot/$fileName');
      if (!await repairedFile.exists()) {
        throw StateError('Bundled GeoGebra page is missing: $fileName');
      }
      return repairedFile.path;
    }
    return file.path;
  }

  static Future<String> _install() async {
    final Directory documents = await getApplicationDocumentsDirectory();
    final Directory runtime = Directory(
      '${documents.path}/geogebra/$runtimeVersion',
    );
    final File marker = File('${runtime.path}/$_completionMarker');
    final File loader = File('${runtime.path}/web3d/web3d.nocache.js');

    final String manifestText = await rootBundle.loadString(_manifestAsset);
    final List<String> files = manifestText
        .split('\n')
        .map((String value) => value.trim())
        .where((String value) => value.isNotEmpty)
        .toList(growable: false);
    final String expectedMarker = '$runtimeVersion:${files.length}';

    if (await marker.exists() &&
        await loader.exists() &&
        await marker.readAsString() == expectedMarker) {
      return runtime.path;
    }

    if (await runtime.exists()) {
      await runtime.delete(recursive: true);
    }
    await runtime.create(recursive: true);

    for (final String relativePath in files) {
      final ByteData data = await rootBundle.load('$_assetRoot/$relativePath');
      final File target = File('${runtime.path}/$relativePath');
      await target.parent.create(recursive: true);
      await target.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: false,
      );
    }

    await marker.writeAsString(expectedMarker, flush: true);
    return runtime.path;
  }
}
