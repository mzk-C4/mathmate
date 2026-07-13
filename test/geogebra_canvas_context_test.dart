import 'package:flutter_test/flutter_test.dart';
import 'package:mathmate/geogebra/geogebra_canvas_context.dart';

void main() {
  const parser = GeogebraCanvasContextParser();

  test('parses elements, coordinates, expressions and selection', () {
    const xml = '''
      <geogebra>
        <construction>
          <expression label="A" exp="(1, 2)" />
          <element type="point" label="A">
            <coords x="1" y="2" z="1" />
          </element>
          <expression label="f" exp="x^2" />
          <element type="function" label="f">
            <value val="2" />
          </element>
        </construction>
      </geogebra>
    ''';

    final context = parser.parse(xml, selectedObjects: const <String>['A']);

    expect(context.elements, hasLength(2));
    expect(context.elements.first['label'], 'A');
    expect(context.elements.first['coordinates'], <String, num>{
      'x': 1,
      'y': 2,
      'z': 1,
    });
    expect(context.elements.first['definition'], '(1, 2)');
    expect(context.expressions, hasLength(2));
    expect(context.selectedObjects, <String>['A']);
  });

  test('returns an empty context for empty XML', () {
    final context = parser.parse('');
    expect(context.elements, isEmpty);
    expect(context.expressions, isEmpty);
  });
}
