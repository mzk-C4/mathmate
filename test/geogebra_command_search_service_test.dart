import 'package:flutter_test/flutter_test.dart';
import 'package:mathmate/geogebra/geogebra_command_search_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('finds bundled GeoGebra commands without a network request', () async {
    final results = await GeogebraCommandSearchService.instance.search(
      'semicircle',
      limit: 5,
    );

    expect(results, isNotEmpty);
    expect(
      results.map((result) => result['commandBase']),
      contains('Semicircle'),
    );
  });

  test('returns no commands for an empty query', () async {
    final results = await GeogebraCommandSearchService.instance.search('  ');
    expect(results, isEmpty);
  });

  test('exposes normalized names for runtime plan validation', () async {
    final Set<String> commands = await GeogebraCommandSearchService.instance
        .supportedCommandNames();

    expect(commands, containsAll(<String>['circle', 'polygon', 'rotate']));
    expect(commands, isNot(contains('RegularPolygon')));
  });
}
