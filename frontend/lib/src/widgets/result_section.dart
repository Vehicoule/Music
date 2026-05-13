import '../models.dart';

class ResultSection {
  const ResultSection(this.label, this.items);

  final String label;
  final List<DiscoverItem> items;
}

List<ResultSection> groupedResults(List<DiscoverItem> results) {
  final order = [
    ('Songs', 'song'),
    ('Albums', 'album'),
    ('Artists', 'artist'),
    ('Videos', 'video'),
    ('Metadata', 'metadata'),
  ];
  final sections = <ResultSection>[];
  for (final (label, kind) in order) {
    final items = results.where((item) => item.kind == kind).toList();
    if (items.isNotEmpty) {
      sections.add(ResultSection(label, items));
    }
  }
  final remaining = results
      .where((item) => !order.any((entry) => entry.$2 == item.kind))
      .toList();
  if (remaining.isNotEmpty) {
    sections.add(ResultSection('Results', remaining));
  }
  return sections;
}
