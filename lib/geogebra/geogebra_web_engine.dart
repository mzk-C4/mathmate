// ignore_for_file: avoid_web_libraries_in_flutter

import 'package:mathmate/geogebra/geometry_engine.dart';
import 'package:mathmate/visualization/geogebra_web_renderer.dart';

/// Web-only adapter that lets the shared transaction executor use the iframe
/// bridge without leaking static bridge calls into the geometry domain layer.
class GeogebraWebEngine implements GeometryEngine {
  const GeogebraWebEngine();

  @override
  Future<GeometryEngineCommandResult> executeCommand(String command) async {
    final Map<String, dynamic> result = await GeogebraJSBridge.evalCommand(
      command,
    );
    return GeometryEngineCommandResult(
      success: result['success'] == true,
      label: result['label']?.toString(),
      error: result['error']?.toString(),
    );
  }

  @override
  Future<String> getXML() => GeogebraJSBridge.getXML();

  @override
  Future<bool> setUndoPoint() => GeogebraJSBridge.setUndoPoint();

  @override
  Future<bool> setXML(String xml) => GeogebraJSBridge.setXML(xml);
}
