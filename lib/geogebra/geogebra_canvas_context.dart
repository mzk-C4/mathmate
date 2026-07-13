import 'dart:convert';

class GeogebraCanvasContext {
  const GeogebraCanvasContext({
    required this.elements,
    required this.expressions,
    required this.selectedObjects,
  });

  final List<Map<String, dynamic>> elements;
  final List<Map<String, dynamic>> expressions;
  final List<String> selectedObjects;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'elements': elements,
    'expressions': expressions,
    'selectedObjects': selectedObjects,
  };

  @override
  String toString() => jsonEncode(toJson());
}

class GeogebraCanvasContextParser {
  const GeogebraCanvasContextParser();

  GeogebraCanvasContext parse(
    String xml, {
    List<String> selectedObjects = const <String>[],
  }) {
    if (xml.trim().isEmpty) {
      return GeogebraCanvasContext(
        elements: const <Map<String, dynamic>>[],
        expressions: const <Map<String, dynamic>>[],
        selectedObjects: List<String>.unmodifiable(selectedObjects),
      );
    }

    final List<Map<String, dynamic>> expressions = _parseExpressions(xml);
    final Map<String, String> definitions = <String, String>{
      for (final expression in expressions)
        if (expression['label'] is String && expression['value'] is String)
          expression['label'] as String: expression['value'] as String,
    };

    final List<Map<String, dynamic>> elements = <Map<String, dynamic>>[];
    final RegExp elementPattern = RegExp(
      r'<element\b([^>]*)>([\s\S]*?)</element>',
      caseSensitive: false,
    );
    for (final RegExpMatch match in elementPattern.allMatches(xml)) {
      final Map<String, String> attributes = _attributes(match.group(1) ?? '');
      final String? label = attributes['label'];
      final String? type = attributes['type'];
      if (label == null || type == null) continue;

      final Map<String, dynamic> element = <String, dynamic>{
        'label': label,
        'type': type,
      };
      final String body = match.group(2) ?? '';
      final RegExpMatch? coordinates = RegExp(
        r'<coords\b([^>]*)/?>',
        caseSensitive: false,
      ).firstMatch(body);
      if (coordinates != null) {
        final Map<String, String> coords = _attributes(
          coordinates.group(1) ?? '',
        );
        element['coordinates'] = <String, num>{
          for (final axis in const <String>['x', 'y', 'z'])
            if (num.tryParse(coords[axis] ?? '') case final num value)
              axis: value,
        };
      }

      final RegExpMatch? valueTag = RegExp(
        r'<value\b([^>]*)/?>',
        caseSensitive: false,
      ).firstMatch(body);
      if (valueTag != null) {
        final String? value = _attributes(valueTag.group(1) ?? '')['val'];
        if (value != null) element['value'] = value;
      }
      if (definitions[label] case final String definition) {
        element['definition'] = definition;
      }
      elements.add(element);
    }

    return GeogebraCanvasContext(
      elements: List<Map<String, dynamic>>.unmodifiable(elements),
      expressions: List<Map<String, dynamic>>.unmodifiable(expressions),
      selectedObjects: List<String>.unmodifiable(selectedObjects),
    );
  }

  List<Map<String, dynamic>> _parseExpressions(String xml) {
    final List<Map<String, dynamic>> result = <Map<String, dynamic>>[];
    final RegExp expressionPattern = RegExp(
      r'<expression\b([^>]*)/?>',
      caseSensitive: false,
    );
    for (final RegExpMatch match in expressionPattern.allMatches(xml)) {
      final Map<String, String> attributes = _attributes(match.group(1) ?? '');
      final String? label = attributes['label'];
      final String? value = attributes['exp'] ?? attributes['value'];
      if (label == null || value == null) continue;
      result.add(<String, dynamic>{'label': label, 'value': value});
    }
    return result;
  }

  Map<String, String> _attributes(String source) {
    final Map<String, String> result = <String, String>{};
    final RegExp attributePattern = RegExp(
      r'''([\w:-]+)\s*=\s*["']([^"']*)["']''',
    );
    for (final RegExpMatch match in attributePattern.allMatches(source)) {
      result[match.group(1)!] = _decodeEntities(match.group(2)!);
    }
    return result;
  }

  String _decodeEntities(String value) {
    return value
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
  }
}
