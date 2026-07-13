class GeochatHistoryEntry {
  const GeochatHistoryEntry({
    required this.role,
    required this.content,
    this.isStreaming = false,
  });

  final String role;
  final String content;
  final bool isStreaming;
}

class GeochatHistoryBuilder {
  const GeochatHistoryBuilder();

  List<Map<String, String>> build(Iterable<GeochatHistoryEntry> entries) {
    return entries
        .where(
          (GeochatHistoryEntry entry) =>
              !entry.isStreaming && entry.content.trim().isNotEmpty,
        )
        .map(
          (GeochatHistoryEntry entry) => <String, String>{
            'role': entry.role,
            'content': entry.content,
          },
        )
        .toList(growable: false);
  }
}
