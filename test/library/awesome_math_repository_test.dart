import 'package:flutter_test/flutter_test.dart';
import 'package:mathmate/library/models/awesome_resource.dart';
import 'package:mathmate/library/services/awesome_math_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<AwesomeMathResource> resources;

  setUpAll(() async {
    resources = await AwesomeMathRepository.instance.load();
  });

  test('loads a non-empty, valid external-link index', () {
    expect(resources, isNotEmpty);
    expect(resources.map((r) => r.id).toSet().length, resources.length);
    expect(resources.map((r) => r.url).toSet().length, resources.length);

    for (final AwesomeMathResource resource in resources) {
      expect(resource.id, matches(RegExp(r'^awm_[0-9a-f]{12}$')));
      final Uri? uri = Uri.tryParse(resource.url);
      expect(uri, isNotNull);
      expect(<String>{'http', 'https'}, contains(uri!.scheme));
      expect(uri.host, isNotEmpty);
      expect(resource.title, isNotEmpty);
    }
  });

  test('does not ship video resources', () {
    expect(
      resources.where(
        (r) => r.url.contains('youtube.com') || r.url.contains('youtu.be'),
      ),
      isEmpty,
    );
  });

  test('filters by type, stage, category, and keyword', () {
    final AwesomeMathRepository repository = AwesomeMathRepository.instance;

    expect(repository.filter(type: ResourceType.book), isNotEmpty);
    expect(repository.filter(stage: LearnStage.middle), isNotEmpty);
    expect(repository.filter(category: 'Analysis'), isNotEmpty);
    expect(repository.filter(keyword: 'calculus'), isNotEmpty);
    expect(repository.filter(keyword: 'definitely-not-a-resource'), isEmpty);
  });
}
