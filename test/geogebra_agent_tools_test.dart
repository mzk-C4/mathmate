import 'package:flutter_test/flutter_test.dart';
import 'package:mathmate/services/geogebra_agent_service.dart';

void main() {
  test('advertises transactional plan execution instead of raw commands', () {
    final Map<String, AgentTool> tools = <String, AgentTool>{
      for (final AgentTool tool in geogebraTools) tool.name: tool,
    };

    expect(tools, contains('executeGeoGebraPlan'));
    expect(tools, isNot(contains('executeGeoGebraCommand')));
    expect(tools, isNot(contains('setUndoPoint')));
    final Map<String, dynamic> parameters =
        tools['executeGeoGebraPlan']!.parameters;
    final Map<String, dynamic> commands =
        (parameters['properties'] as Map<String, dynamic>)['commands']
            as Map<String, dynamic>;
    expect(commands['type'], 'array');
    expect(commands['maxItems'], 32);
  });
}
