import '../models.dart';

abstract interface class TrackResolver {
  Future<List<DiscoverItem>> search(String query, {int limit = 15});
  Future<SourceCandidate> resolve(String url);
}
